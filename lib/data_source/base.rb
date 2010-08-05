module GoogleDataSource
  module DataSource
    # Superclass for all data source implementations
    # Offers methods for getting and setting the data and column definitions of
    # the data source
    class Base
      # Callback defines a JavaScript snippet that is appended to the regular
      # data-source reponse. This is currently used to refresh the form in
      # reportings (validation)
      attr_accessor :callback

      # Define accessors for the data source data, columns and errors
      attr_reader :data, :cols, :errors
      
      # Creates a new instance and validates it. 
      # Protected method so it can be used from the subclasses
      def initialize(gdata_params)
        @params = gdata_params
        @errors = {}
        @cols = []
        @data = []
        @version = "0.6"
        @coltypes = [ "boolean", "number", "string", "date", "datetime", "timeofday"]
        @colkeys = [:type, :id, :label, :pattern]
      
        validate
      end
      protected :initialize
      
      # Creates a new data source object from the get parameters of the data-source
      # request.
      def self.from_params(params)
        # Exract GDataSource params from the request.
        gdata_params = {}
        tqx = params[:tqx]
        unless tqx.blank?
          gdata_params[:tqx] = true
          tqx.split(';').each do |kv|
            key, value = kv.split(':')
            gdata_params[key.to_sym] = value
          end
        end
      
        # Create the appropriate GDataSource instance from the gdata-specific parameters
        gdata_params[:out] ||= "json"    
        gdata = from_gdata_params(gdata_params)
      end
      
      # Factory method to create a GDataSource instance from a serie of valid GData
      # parameters, as described in the official documentation (see above links).
      # 
      # +gdata_params+ can be any map-like object that maps keys (like +:out+, +:reqId+
      # and so forth) to their values. Keys must be symbols.
      def self.from_gdata_params(gdata_params)
        case gdata_params[:out]
        when "json"
          JsonData.new(gdata_params)
        when "html"
          HtmlData.new(gdata_params)
        when "csv"
          CsvData.new(gdata_params)
        else
          InvalidData.new(gdata_params)
        end
      end
      
      # Access a GData parameter. +k+ must be symbols, like +:out+, +:reqId+.
      def [](k)
        @params[k]
      end
    
      # Sets a GData parameter. +k+ must be symbols, like +:out+, +:reqId+.
      # The instance is re-validated afterward.
      def []=(k, v)
        @params[k] = v
        validate
      end
    
      # Checks whether this instance is valid (in terms of configuration parameters)
      # or not.
      def valid?
        @errors.size == 0
      end
    
      # Manually adds a new validation error. +key+ should be a symbol pointing
      # to the invalid parameter or element.
      def add_error(key, message)
        @errors[key] = message
        return self
      end
      
      # TODO inline this method in +set+
      #
      # Sets the data to be exported. +data+ should be a collection of activerecord object. The 
      # first index should iterate over rows, the second over columns. Column 
      # ordering must be the same used in +add_col+ invokations.
      #
      # Anything that behaves like a 2-dimensional array and supports +each+ is
      # a perfectly fine alternative.
      def set_raw(cols, data)
        cols.each do |col|
          raise ArgumentError, "Invalid column type: #{col.type}" if !@coltypes.include?(col.type)
          @cols << col.data
        end
        # @data should be a 2-dimensional array
        @data = []
        data.each do |record|
          @data << record
        end
        #data
        return self
      end
      
      # Set data and columns of the data source.
      # +items+ can be either:
      # * A collection of +ActiveRecord+ objects
      # * A collection of +Array+s
      # * A collection of objects that respond to a +to_a+ method
      # * A collection of abitrary object if a block is passed to the method
      #
      # +columns+ can be either:
      # * +nil+, the columns are then guessed from the +items+ collection
      # * A collection of +GoogleDataSource::Column+ objects
      # * A collection of +Hash+es which are then converted to +Column+ objects
      #
      # The method takes an optional block which is called for each entry of +items+
      # The block is supposed to return an array (one entry per column) for each entry
      # of +items+.
      def set(items, columns = nil)
        if items.is_a?(::Reporting)
          add_error(:reqId, "Form validation failed") and return unless items.valid?
          return set(items.data, columns || items.columns)
        end

        columns ||= guess_columns(items)
        columns.map! { |c| c.is_a?(Column) ? c : Column.new(c) }

        data = []
        items.each do |item|
          # use block for row formating
          if block_given?
            data << yield(item)
          # use object if it is already an array
          elsif item.is_a?(Array)
            data << item
          # use column ids if item is an active record
          elsif item.is_a?(ActiveRecord::Base)
            data << columns.map { |c| item.send(c.id) }
          # use to_array method
          else
            data << item.to_a
          end
        end
        set_raw(columns, data)
      end

      # Tries to get a clever column selection from the items collection.
      # Currently only accounts for ActiveRecord objects
      # +items+ is an arbitrary collection of items as passed to the +set+ method
      def guess_columns(items)
        columns = []
        klass = items.first.class
        klass.columns.each do |column|
          columns << Column.new({
            :id => column.name,
            :label => column.name.humanize,
            :type => 'string' # TODO get the right type
          })
        end
        columns
      end

      # Validates this instance by checking that the configuration parameters
      # conform to the official specs.
      def validate
        @errors.clear
        if @params[:tqx]
          add_error(:reqId, "Missing required parameter reqId") unless @params[:reqId]
        
          if @params[:version] && @params[:version] != @version
            add_error(:version, "Unsupported version #{@params[:version]}")
          end
        end
      end
    
      # Empty method. This is a placeholder implemented by subclasses that
      # produce the response according to a given format.
      def response
      end
      
      # Empty method. This is a placeholder implemented by subclasses that return the correct format
      def format
      end
    end
  end
end