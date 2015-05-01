/*
 * Copyright 2014 Google Inc. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file or at
 * https://developers.google.com/open-source/licenses/bsd
 */

part of charted.charts;

class LineChartRenderer extends CartesianRendererBase {
  final Iterable<int> dimensionsUsingBand = const[];
  final SubscriptionsDisposer _disposer = new SubscriptionsDisposer();

  final bool alwaysAnimate;
  final bool trackDataPoints;
  final bool trackOnDimensionAxis;
  final int quantitativeScaleProximity;

  bool _trackingPointsCreated = false;
  List _xPositions = [];
  int currentDataIndex = -1;

  @override
  final String name = "line-rdr";

  LineChartRenderer({
      this.alwaysAnimate: false,
      this.trackDataPoints: true,
      this.trackOnDimensionAxis: false,
      this.quantitativeScaleProximity: 5 });

  /*
   * Returns false if the number of dimension axes on the area is 0.
   * Otherwise, the first dimension scale is used to render the chart.
   */
  @override
  bool prepare(ChartArea area, ChartSeries series) {
    _ensureAreaAndSeries(area, series);
    if (trackDataPoints != false) {
      _trackPointerInArea();
    }
    return area is CartesianArea;
  }

  @override
  void draw(Element element, {Future schedulePostRender}) {
    _ensureReadyToDraw(element);

    var measureScale = area.measureScales(series).first,
        dimensionScale = area.dimensionScales.first;

    // Create lists of values in measure columns.
    var lines = series.measures.map((column) {
      return area.data.rows.map((values) => values[column]).toList();
    }).toList();

    // We only support one dimension axes, so we always use the
    // first dimension.
    var x = area.data.rows.map(
        (row) => row.elementAt(area.config.dimensions.first)).toList();

    var rangeBandOffset =
        dimensionScale is OrdinalScale ? dimensionScale.rangeBand / 2 : 0;

    // If tracking data points is enabled, cache location of points that
    // represent data.
    if (trackDataPoints) {
      _xPositions =
          x.map((val) => dimensionScale.scale(val) + rangeBandOffset).toList();
    }

    var line = new SvgLine(
        xValueAccessor: (d, i) => dimensionScale.scale(x[i]) + rangeBandOffset,
        yValueAccessor: (d, i) => measureScale.scale(d));

    // Add lines and hook up hover and selection events.
    var svgLines = root.selectAll('.line-rdr-line').data(lines);
    svgLines.enter.append('path')
        ..each((d, i, e) {
          e.classes.add('line-rdr-line');
          e.attributes['fill'] = 'none';
        });

    svgLines.each((d, i, e) {
      var column = series.measures.elementAt(i),
          color = colorForColumn(column),
          styles = stylesForColumn(column);
      e.classes.addAll(styles);
      e.attributes
        ..['d'] = line.path(d, i, e)
        ..['stroke'] = color
        ..['data-column'] = '$column';
    });

    if (area.state != null) {
      svgLines
        ..on('click', (d, i, e) => _mouseClickHandler(d, i, e))
        ..on('mouseover', (d, i, e) => _mouseOverHandler(d, i, e))
        ..on('mouseout', (d, i, e) => _mouseOutHandler(d, i, e));
    }

    svgLines.exit.remove();
  }

  @override
  void dispose() {
    if (root == null) return;
    root.selectAll('.line-rdr-line').remove();
    root.selectAll('.line-rdr-point').remove();
    _disposer.dispose();
  }

  @override
  void handleStateChanges(List<ChangeRecord> changes) {
    var lines = host.querySelectorAll('.line-rdr-line');
    if (lines == null || lines.isEmpty) return;

    for (int i = 0, len = lines.length; i < len; ++i) {
      var line = lines.elementAt(i),
          column = int.parse(line.dataset['column']);
      line.classes.removeAll(ChartState.COLUMN_CLASS_NAMES);
      line.classes.addAll(stylesForColumn(column));
      line.attributes['stroke'] = colorForColumn(column);
    }
  }

  void _createTrackingCircles() {
    var linePoints = root.selectAll('.line-rdr-point').data(series.measures);
    linePoints.enter.append('circle').each((d, i, e) {
      e.classes.add('line-rdr-point');
      e.attributes['r'] = '4';
    });

    linePoints
      ..each((d, i, e) {
      var color = colorForColumn(d);
      e.attributes
        ..['r'] = '4'
        ..['stroke'] = color
        ..['fill'] = color
        ..['data-column'] = '$d';
    })
      ..on('click', _mouseClickHandler)
      ..on('mouseover', _mouseOverHandler)
      ..on('mouseout', _mouseOutHandler);

    linePoints.exit.remove();
    _trackingPointsCreated = true;
  }

  void _showTrackingCircles(int row) {
    if (_trackingPointsCreated == false) {
      _createTrackingCircles();
    }

    var yScale = area.measureScales(series).first;
    root.selectAll('.line-rdr-point').each((d, i, e) {
      var x = _xPositions[row],
          y = yScale.scale(area.data.rows.elementAt(row).elementAt(d));
      e.attributes
        ..['cx'] = '$x'
        ..['cy'] = '$y'
        ..['fill'] = colorForColumn(d)
        ..['stroke'] = colorForColumn(d)
        ..['data-row'] = '$row';
      e.style
        ..setProperty('opacity', '1')
        ..setProperty('visibility', 'visible');
    });
  }

  void _hideTrackingCircles() {
    root.selectAll('.line-rdr-point')
      ..style('opacity', '0.0')
      ..style('visibility', 'hidden');
  }

  int _getNearestRowIndex(double x) {
    var lastSmallerValue = 0;
    var chartX = x - area.layout.renderArea.x;
    for (var i = 0; i < _xPositions.length; i++) {
      var pos = _xPositions[i];
      if (pos < chartX) {
        lastSmallerValue = pos;
      } else {
        return i == 0 ? 0 :
          (chartX - lastSmallerValue <= pos - chartX) ? i - 1 : i;
      }
    }
    return _xPositions.length - 1;
  }

  void _trackPointerInArea() {
    _trackingPointsCreated = false;
    _disposer.add(area.onMouseMove.listen((ChartEvent event) {
      if (area.layout.renderArea.contains(event.chartX, event.chartY)) {
        var renderAreaX = event.chartX - area.layout.renderArea.x,
            row = _getNearestRowIndex(event.chartX);
        window.animationFrame.then((_) => _showTrackingCircles(row));
      } else {
        _hideTrackingCircles();
      }
    }));
    _disposer.add(area.onMouseOut.listen((ChartEvent event) {
      _hideTrackingCircles();
    }));
  }

  void _mouseClickHandler(d, int i, Element e) {
    area.state.select(int.parse(e.dataset['column']));
    if (mouseClickController != null && e.tagName == 'circle') {
      var row = int.parse(e.dataset['row']),
          column = int.parse(e.dataset['column']);
      mouseClickController.add(
          new _ChartEvent(scope.event, area, series, row, column, d));
    }
  }

  void _mouseOverHandler(d, i, e) {
    area.state.preview = int.parse(e.dataset['column']);
    if (mouseOverController != null && e.tagName == 'circle') {
      var row = int.parse(e.dataset['row']),
          column = int.parse(e.dataset['column']);
      mouseOverController.add(
          new _ChartEvent(scope.event, area, series, row, column, d));
    }
  }

  void _mouseOutHandler(d, i, e) {
    if (area.state.preview == int.parse(e.dataset['column'])) {
      area.state.preview = null;
    }
    if (mouseOutController != null && e.tagName == 'circle') {
      var row = int.parse(e.dataset['row']),
          column = int.parse(e.dataset['column']);
      mouseOutController.add(
          new _ChartEvent(scope.event, area, series, row, column, d));
    }
  }
}