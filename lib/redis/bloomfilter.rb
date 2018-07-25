# frozen_string_literal: true

class Redis
  class Bloomfilter
    attr_reader :options
    attr_reader :driver

    # Usage: Redis::Bloomfilter.new :size => 1000, :error_rate => 0.01
    # It creates a bloomfilter with a capacity of 1000 items and an error rate of 1%
    def initialize(options = {})
      @options = {
        size: 1000,
        error_rate: 0.01,
        key_name: 'redis-bloomfilter',
        hash_engine: 'md5',
        default_expire: nil,
        redis: Redis.current,
        driver: nil
      }.merge options

      raise ArgumentError, 'options[:size] && options[:error_rate] cannot be nil' if options[:error_rate].nil? || options[:size].nil?

      # Size provided, compute hashes and bits

      @options[:size]       = options[:size]
      @options[:error_rate] = options[:error_rate] ? options[:error_rate] : @options[:error_rate]
      @options[:bits]       = Bloomfilter.optimal_m options[:size], @options[:error_rate]
      @options[:hashes]     = Bloomfilter.optimal_k options[:size], @options[:bits]

      @redis = @options[:redis] || Redis.current
      @options[:hash_engine] = options[:hash_engine] if options[:hash_engine]

      if @options[:driver].nil?
        ver = @redis.info['redis_version']

        @options[:driver] = if Gem::Version.new(ver) >= Gem::Version.new('2.6.0')
                              'lua'
                            else
                              'ruby'
                            end
      end

      driver_class = Redis::BloomfilterDriver.const_get(driver_name)
      @driver = driver_class.new @options
      @driver.redis = @redis
    end

    # Methods used to calculate M and K
    # Taken from http://en.wikipedia.org/wiki/Bloom_filter#Probability_of_false_positives
    def self.optimal_m(num_of_elements, false_positive_rate = 0.01)
      (-1 * num_of_elements * Math.log(false_positive_rate) / (Math.log(2)**2)).round
    end

    def self.optimal_k(num_of_elements, bf_size)
      h = (Math.log(2) * (bf_size / num_of_elements)).round
      h += 1 if h.zero?
      h
    end

    # Does a Check And Set, this will not add the element if it already exist.
    # `insert` will return `false` if the element is added, or `true` if the element was already in the filter.
    # Since we use a scaling filter adding an element using `insert!` might cause the element to exist in multiple parts of the filter at the same time.
    # `insert` prevents this. Using only `insert` the :count key of the filter will accurately count the number of elements added to the filter.
    # Only using `insert` will also lower the number of false positives by a small amount (less duplicates in the filter means less bits set).
    def insert(data, expire = nil)
      @driver.insert(data, expire || @options[:default_expire])
    end

    # Adds a new element to the filter. It will create the filter when it doesn't exist yet.
    def insert!(data, expire = nil)
      @driver.insert!(data, expire || @options[:default_expire])
    end

    # It checks if a key is part of the set
    def include?(key)
      @driver.include?(key)
    end

    # It deletes a bloomfilter
    def clear
      @driver.clear
    end

    protected

    def driver_name
      @options[:driver].downcase.split('-').collect { |t| t.gsub(/(\w+)/, &:capitalize) }.join
    end
  end
end
