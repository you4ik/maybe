import { Controller } from "@hotwired/stimulus";
import tailwindColors from "@maybe/tailwindcolors";
import * as d3 from "d3";

export default class extends Controller {
  static values = { series: Object };

  connect() {
    this.renderChart(this.seriesValue);
    document.addEventListener("turbo:load", this.renderChart);
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.renderChart);
  }

  renderChart = () => {
    const data = this.prepareData(this.seriesValue);
    this.drawChart(data);
  };

  prepareData(series) {
    return series.values.map((d) => ({
      date: new Date(d.date + "T00:00:00"),
      value: +d.value.amount,
    }));
  }

  drawChart(data) {
    const chartContainer = d3.select(this.element);
    chartContainer.selectAll("*").remove();
    const initialDimensions = {
      width: chartContainer.node().clientWidth,
      height: chartContainer.node().clientHeight,
    };

    const svg = chartContainer
      .append("svg")
      .attr("width", initialDimensions.width)
      .attr("height", initialDimensions.height)
      .attr("viewBox", [
        0,
        0,
        initialDimensions.width,
        initialDimensions.height,
      ])
      .attr("style", "max-width: 100%; height: auto; height: intrinsic;");

    const margin = { top: 0, right: 0, bottom: 0, left: 0 };
    const width = initialDimensions.width - margin.left - margin.right;
    const height = initialDimensions.height - margin.top - margin.bottom;

    const isLiability = this.classificationValue === "liability";
    const trendDirection = data[data.length - 1].value - data[0].value;
    let lineColor;

    if (trendDirection > 0) {
      lineColor = isLiability
        ? tailwindColors.error
        : tailwindColors.green[500];
    } else if (trendDirection < 0) {
      lineColor = isLiability
        ? tailwindColors.green[500]
        : tailwindColors.error;
    } else {
      lineColor = tailwindColors.gray[500];
    }

    const xScale = d3
      .scaleTime()
      .rangeRound([0, width])
      .domain(d3.extent(data, (d) => d.date));

    const PADDING = 0.05;
    const dataMin = d3.min(data, (d) => d.value);
    const dataMax = d3.max(data, (d) => d.value);
    const padding = (dataMax - dataMin) * PADDING;

    const yScale = d3
      .scaleLinear()
      .rangeRound([height, 0])
      .domain([dataMin - padding, dataMax + padding]);

    const line = d3
      .line()
      .x((d) => xScale(d.date))
      .y((d) => yScale(d.value));

    svg
      .append("path")
      .datum(data)
      .attr("fill", "none")
      .attr("stroke", lineColor)
      .attr("stroke-width", 2)
      .attr("d", line);
  }
}
