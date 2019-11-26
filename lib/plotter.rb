require 'silicium'
require 'chunky_png'
require 'ruby2d'


module Silicium
  module Plotter
    #
    # Factory method to return a color value, based on the arguments given.
    #
    # @overload Color(r, g, b, a)
    #   @param (see ChunkyPNG::Color.rgba)
    #   @return [Integer] The rgba color value.
    #
    # @overload Color(r, g, b)
    #   @param (see ChunkyPNG::Color.rgb)
    #   @return [Integer] The rgb color value.
    #
    # @overload Color(hex_value, opacity = nil)
    #   @param (see ChunkyPNG::Color.from_hex)
    #   @return [Integer] The hex color value, with the opacity applied if one
    #     was given.
    #
    # @overload Color(color_name, opacity = nil)
    #   @param (see ChunkyPNG::Color.html_color)
    #   @return [Integer] The hex color value, with the opacity applied if one
    #     was given.
    #
    # @overload Color(color_value, opacity = nil)
    #   @param [Integer, :to_i] The color value.
    #   @return [Integer] The color value, with the opacity applied if one was
    #     given.
    #
    # @return [Integer] The determined color value as RGBA integer.
    # @raise [ArgumentError] if the arguments weren't understood as a color.
    def color(*args)
      case args.length
      when 1; ChunkyPNG::Color.parse(args.first)
      when 2; (ChunkyPNG::Color.parse(args.first) & 0xffffff00) | args[1].to_i
      when 3; ChunkyPNG::Color.rgb(*args)
      when 4; ChunkyPNG::Color.rgba(*args)
      else raise ArgumentError, "Don't know how to create a color from #{args.inspect}!"
      end
    end
    ##
    # A class representing canvas for plotting bar charts and function graphs
    class Image
      ##
      # Creates a new plot with chosen +width+ and +height+ parameters
      # with background colored +bg_color+
      def initialize(width, height, bg_color = ChunkyPNG::Color::TRANSPARENT)
        @image = ChunkyPNG::Image.new(width, height, bg_color)
      end

      def rectangle(x, y, width, height, color)
        x_end = x + width - 1
        y_end = y + height - 1
        (x..x_end).each do |i|
          (y..y_end).each do |j|
            @image[i, j] = color
          end
        end
      end

      ##
      # Draws a bar chart in the plot using provided +bars+,
      # each of them has width of +bar_width+ and colored +bars_color+
      def bar_chart(bars, bar_width, bars_color = ChunkyPNG::Color('red @ 1.0'), axis_color = ChunkyPNG::Color::BLACK)
        if bars.count * bar_width > @image.width
          raise ArgumentError, 'Not enough big size of image to plot these number of bars'
        end

        padding = 5
        # Values of x and y on borders of plot
        minx = [bars.collect { |k, _| k }.min, 0].min
        maxx = [bars.collect { |k, _| k }.max, 0].max
        miny = [bars.collect { |_, v| v }.min, 0].min
        maxy = [bars.collect { |_, v| v }.max, 0].max
        dpux = Float((@image.width - 2 * padding)) / (maxx - minx + bar_width) # Dots per unit for X
        dpuy = Float((@image.height - 2 * padding)) / (maxy - miny) # Dots per unit for Y
        rectangle(padding, @image.height - padding - (miny.abs * dpuy).ceil, @image.width - 2 * padding, 1, axis_color) # Axis OX
        rectangle(padding + (minx.abs * dpux).ceil, padding, 1, @image.height - 2 * padding, axis_color) # Axis OY

        bars.each do |x, y| # Cycle drawing bars
          rectangle(padding + ((x + minx.abs) * dpux).floor,
                    @image.height - padding - (([y, 0].max + miny.abs) * dpuy).ceil + (y.negative? ? 1 : 0),
                    bar_width, (y.abs * dpuy).ceil, bars_color)
        end
      end

      ##
      # Exports plotted image to file +filename+
      def export(filename)
        @image.save(filename, :interlace => true)
      end
    end

    CENTER_X = Window.width / 2
    CENTER_Y = Window.height / 2
    mul = 100/1

    ##
    # draws axes
    def draw_axes
      Line.new(x1: 0, y1: CENTER_Y, x2: (get :width), y2: CENTER_Y, width: 1, color: 'white', z: 20)
      Line.new(x1: CENTER_X, y1: 0, x2: CENTER_X, y2: (get :height), width: 1, color: 'white', z: 20)

      x1 = CENTER_X
      x2 = CENTER_X
      while (x1 < Window.width * 1.1) and (x2 > Window.width * -1.1) do
        Line.new(x1: x1, y1: CENTER_Y - 4, x2: x1, y2: CENTER_Y + 3, width: 1, color: 'white', z: 20)
        Line.new(x1: x2, y1: CENTER_Y - 4, x2: x2, y2: CENTER_Y + 3, width: 1, color: 'white', z: 20)
        x1 += mul
        x2 -= mul
      end

      y1 = CENTER_Y
      y2 = CENTER_Y
      while (y1 < Window.height * 1.1) and (y2 > Window.height * -1.1) do
        Line.new(x1: CENTER_X - 3, y1: y1, x2: CENTER_X + 3, y2: y1, width: 1, color: 'white', z: 20)
        Line.new(x1: CENTER_X - 3, y1: y2, x2: CENTER_X + 3, y2: y2, width: 1, color: 'white', z: 20)
        y1 += mul
        y2 -= mul
      end
    end

    ##
    # Changes the coordinates to draw the next pixel for the +f+ function
    # +x+ - current argument. +st+ - step to next point
    def reset_step(x, st, &f)
      y1 = f.call(x)
      y2 = f.call(x + st)

      if (y1 - y2).abs / mul > 1.0
        [st / (y1 - y2).abs / mul, 0.001].max
      else
        st / mul * 2
      end
    end

    ##
    # Draws a point on coordinates +x+ and +y+
    # with the scale +mul+ and color +col+
    def draw_point(x, y, mul, col)
      Line.new(
          x1: CENTER_X + x * mul, y1: CENTER_Y - y * mul,
          x2: CENTER_X + 1 + x * mul, y2: CENTER_Y + 2 - y * mul,
          width: 1,
          color: col,
          z: 20
      )
    end

    ##
    # Reduces the interval to the window range. +a+ and +b+ that determine interval
    def reduce_interval(a, b)
      a *= mul
      b *= mul

      return [a, -(get :width) * 1.1].max / mul, [b, (get :width) * 1.1].min / mul
    end

    ##
    # Draws the function +func+ at the interval from +a+ to +b+
    def draw_fn(a, b, &func)
      draw_axes

      a, b = reduce_interval(a, b)

      step = 0.38
      c_step = step
      arg = a

      while arg < b do
        c_step = step
        begin
          c_step = reset_step(arg, step) {|xx| fn(xx)}
        rescue Math::DomainError
          arg += c_step * 0.1
        else
          draw_point(arg, func.call(arg), mul, 'lime')
        ensure
          arg += c_step
        end
      end
    end

    ##
    # show plot
    def show_window
      show
    end

    # @param [Integer] sc
    def set_scale(sc)
      mul = sc
    end

  end
end



