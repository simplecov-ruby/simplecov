# frozen_string_literal: true

module SimpleCov
  module CLI
    module Badge
      # Renders the badge SVG. The geometry follows shields.io's flat
      # style: 20px tall with 3px rounded corners, the label on #555
      # and the value on its ladder color, each text drawn twice for
      # the drop shadow at 10x scale. `textLength` pins the layout, so
      # the estimated segment widths never let glyphs spill.
      module Svg
        extend self

        # The color ladder shields.io applies to coverage percentages,
        # brightgreen down to red.
        COLORS = [[90, "#4c1"], [80, "#97ca00"], [70, "#a4a61d"], [60, "#dfb317"], [50, "#fe7d37"]].freeze

        def color(percent)
          rung = COLORS.detect { |floor, _color| percent >= floor }
          rung ? rung.fetch(1) : "#e05d44"
        end

        # Widths estimate 11px Verdana; `textLength` absorbs the error.
        # The width uses the raw label (what is drawn), while the
        # markup gets the escaped form.
        def render(label:, percent:)
          value = format("%.2f%%", percent)
          document(label: escape(label), value: value, fill: color(percent),
                   geo: geometry(width(label), width(value)))
        end

        def width(text)
          (7 * text.length) + 10
        end

        # The scale(.1) trick draws text at 10x and shrinks it, so the
        # text coordinates live in a 10x space: centers at 10 * (offset
        # + width / 2) and textLength spanning the width less padding.
        def geometry(label_width, value_width)
          {label_width: label_width, value_width: value_width, total: label_width + value_width,
           label_x: 5 * label_width, value_x: (10 * label_width) + (5 * value_width),
           label_span: 10 * (label_width - 10), value_span: 10 * (value_width - 10)}
        end

        def escape(text)
          text.gsub(/[&<>"]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;")
        end

        def document(label:, value:, fill:, geo:)
          <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" width="#{geo.fetch(:total)}" height="20" role="img" aria-label="#{label}: #{value}">
              <title>#{label}: #{value}</title>
              <linearGradient id="s" x2="0" y2="100%">
                <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
                <stop offset="1" stop-opacity=".1"/>
              </linearGradient>
              <clipPath id="r"><rect width="#{geo.fetch(:total)}" height="20" rx="3" fill="#fff"/></clipPath>
              <g clip-path="url(#r)">
                <rect width="#{geo.fetch(:label_width)}" height="20" fill="#555"/>
                <rect x="#{geo.fetch(:label_width)}" width="#{geo.fetch(:value_width)}" height="20" fill="#{fill}"/>
                <rect width="#{geo.fetch(:total)}" height="20" fill="url(#s)"/>
              </g>
              <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
                <text aria-hidden="true" x="#{geo.fetch(:label_x)}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="#{geo.fetch(:label_span)}">#{label}</text>
                <text x="#{geo.fetch(:label_x)}" y="140" transform="scale(.1)" fill="#fff" textLength="#{geo.fetch(:label_span)}">#{label}</text>
                <text aria-hidden="true" x="#{geo.fetch(:value_x)}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="#{geo.fetch(:value_span)}">#{value}</text>
                <text x="#{geo.fetch(:value_x)}" y="140" transform="scale(.1)" fill="#fff" textLength="#{geo.fetch(:value_span)}">#{value}</text>
              </g>
            </svg>
          SVG
        end
      end
    end
  end
end
