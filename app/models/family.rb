class Family < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :transactions, through: :accounts
  has_many :transaction_categories, dependent: :destroy, class_name: "Transaction::Category"

  def snapshot(period = Period.all)
    query = accounts.active.joins(:balances)
      .where("account_balances.currency = ?", self.currency)
      .select(
        "account_balances.currency",
        "account_balances.date",
        "SUM(CASE WHEN accounts.classification = 'liability' THEN account_balances.balance ELSE 0 END) AS liabilities",
        "SUM(CASE WHEN accounts.classification = 'asset' THEN account_balances.balance ELSE 0 END) AS assets",
        "SUM(CASE WHEN accounts.classification = 'asset' THEN account_balances.balance WHEN accounts.classification = 'liability' THEN -account_balances.balance ELSE 0 END) AS net_worth",
      )
      .group("account_balances.date, account_balances.currency")
      .order("account_balances.date")

    query = query.where("account_balances.date >= ?", period.date_range.begin) if period.date_range.begin
    query = query.where("account_balances.date <= ?", period.date_range.end) if period.date_range.end
    result = query.to_a

    {
      asset_series: TimeSeries.new(result.map { |r| { date: r.date, value: Money.new(r.assets, r.currency) } }),
      liability_series: TimeSeries.new(result.map { |r| { date: r.date, value: Money.new(r.liabilities, r.currency) } }),
      net_worth_series: TimeSeries.new(result.map { |r| { date: r.date, value: Money.new(r.net_worth, r.currency) } })
    }
  end

  def effective_start_date
    accounts.active.joins(:balances).minimum("account_balances.date") || Date.current
  end

  def net_worth
    assets - liabilities
  end

  def assets
    Money.new(accounts.active.assets.map { |account| account.balance_money.exchange_to(currency) || 0 }.sum, currency)
  end

  def liabilities
    Money.new(accounts.active.liabilities.map { |account| account.balance_money.exchange_to(currency) || 0 }.sum, currency)
  end

  def sync_accounts
    accounts.each { |account| account.sync_later if account.can_sync? }
  end
end
