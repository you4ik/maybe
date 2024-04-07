class Account::Balance::Calculator
    attr_reader :daily_balances, :errors, :warnings

    @daily_balances = []
    @errors = []
    @warnings = []

    def initialize(account, options = {})
      @account = account
      @calc_start_date = [ options[:calc_start_date], @account.effective_start_date ].compact.max
    end

    def calculate
      prior_balance = implied_start_balance

      calculated_balances = ((@calc_start_date + 1.day)...Date.current).map do |date|
        valuation = normalized_valuations.find { |v| v["date"] == date }

        if valuation
          current_balance = valuation["value"]
        else
          txn_flows = transaction_flows(date)
          current_balance = prior_balance - txn_flows
        end

        prior_balance = current_balance

        { date: date, balance: current_balance, currency: @account.currency, updated_at: Time.current }
      end

      @daily_balances = [
        { date: @calc_start_date, balance: implied_start_balance, currency: @account.currency, updated_at: Time.current },
        *calculated_balances,
        { date: Date.current, balance: @account.balance, currency: @account.currency, updated_at: Time.current } # Last balance must always match "source of truth"
      ]

      if @account.foreign_currency?
        converted_balances = convert_balances_to_family_currency
        @daily_balances.concat(converted_balances)
      end

      self
    end

    private
      def convert_balances_to_family_currency
        rates = ExchangeRate.get_rate_series(
          @account.currency,
          @account.family.currency,
          @calc_start_date..Date.current
        ).to_a

        @daily_balances.map do |balance|
          rate = rates.find { |rate| rate.date == balance[:date] }
          raise "Rate for #{@account.currency} to #{@account.family.currency} on #{balance[:date]} not found" if rate.nil?
          converted_balance = balance[:balance] * rate.rate
          { date: balance[:date], balance: converted_balance, currency: @account.family.currency, updated_at: Time.current }
        end
      end

      # For calculation, all transactions and valuations need to be normalized to the same currency (the account's primary currency)
      def normalize_entries_to_account_currency(entries, value_key)
        entries.map do |entry|
          currency = entry.currency
          date = entry.date
          value = entry.send(value_key)

          if currency != @account.currency
            rate = ExchangeRate.find_by(base_currency: currency, converted_currency: @account.currency, date: date)
            raise "Rate for #{currency} to #{@account.currency} not found" unless rate

            value *= rate.rate
            currency = @account.currency
          end

          entry.attributes.merge(value_key.to_s => value, "currency" => currency)
        end
      end

      def normalized_valuations
        @normalized_valuations ||= normalize_entries_to_account_currency(@account.valuations.where("date >= ?", @calc_start_date).order(:date).select(:date, :value, :currency), :value)
      end

      def normalized_transactions
        @normalized_transactions ||= normalize_entries_to_account_currency(@account.transactions.where("date >= ?", @calc_start_date).order(:date).select(:date, :amount, :currency), :amount)
      end

      def transaction_flows(date)
        flows = normalized_transactions.select { |t| t["date"] == date }.sum { |t| t["amount"] }
        flows *= -1 if @account.classification == "liability"
        flows
      end

      def implied_start_balance
        oldest_valuation_date = normalized_valuations.first&.dig("date")
        oldest_transaction_date = normalized_transactions.first&.dig("date")
        oldest_entry_date = [ oldest_valuation_date, oldest_transaction_date ].compact.min

        if oldest_entry_date == oldest_valuation_date
          oldest_valuation = normalized_valuations.find { |v| v["date"] == oldest_valuation_date }
          oldest_valuation["value"].to_d
        else
          net_transaction_flows = normalized_transactions.sum { |t| t["amount"].to_d }
          net_transaction_flows *= -1 if @account.classification == "liability"
          @account.balance.to_d + net_transaction_flows
        end
      end
end
