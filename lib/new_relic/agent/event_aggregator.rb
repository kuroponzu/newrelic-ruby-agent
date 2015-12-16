# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sampled_buffer'

module NewRelic
  module Agent
    class EventAggregator
      class << self
        def named named = nil
          named ? @named = named.to_s.freeze : @named
        end

        def capacity_key key = nil
          key ? @capacity_key = key : @capacity_key
        end

        def enabled_key key = nil
          key ? @enabled_key = key : @enabled_key
        end
      end

      def initialize
        @lock = Mutex.new
        @buffer = SampledBuffer.new(NewRelic::Agent.config[self.class.capacity_key])
        @enabled = false
        @notified_full = false
        register_capacity_callback
        register_enabled_callback
        after_initialize
      end

      # interface method for subclasses to override to provide post-initialization setup
      def after_initialize
      end

      # interface method for subclasses to override to provide post harvest functionality
      def after_harvest metadata
      end

      def enabled?
        @enabled
      end

      def has_metadata?
        true
      end

      def harvest!
        metadata = nil
        samples = []
        @lock.synchronize do
          samples.concat @buffer.to_a
          metadata = @buffer.metadata
          @buffer.reset!
        end
        after_harvest metadata
        [reservoir_metadata(metadata), samples]
      end

      def merge! payload
        @lock.synchronize do
          _, samples = payload
          @buffer.decrement_lifetime_counts_by samples.count
          samples.each { |s| @buffer.append s }
        end
      end

      def reset!
        @lock.synchronize do
          @buffer.reset!
        end
      end

      private

      def reservoir_metadata metadata
        {
          :reservoir_size => metadata[:capacity],
          :events_seen => metadata[:seen]
        }
      end

      def register_capacity_callback
        NewRelic::Agent.config.register_callback(self.class.capacity_key) do |max_samples|
          NewRelic::Agent.logger.debug "#{self.class.named} max_samples set to #{max_samples}"
          @lock.synchronize do
            @buffer.capacity = max_samples
          end
        end
      end

      def register_enabled_callback
        NewRelic::Agent.config.register_callback(self.class.enabled_key) do |enabled|
          # intentionally unsynchronized for liveness
          @enabled = enabled
          ::NewRelic::Agent.logger.debug "#{self.class.named} will #{enabled ? '' : 'not '}be sent to the New Relic service."
        end
      end

      # method should only be called from within a synchronize block
      def notify_if_full
        return unless !@notified_full && @buffer.full?
        NewRelic::Agent.logger.debug "#{self.class.named} capacity of #{@buffer.capacity} reached, beginning sampling"
        @notified_full = true
      end
    end
  end
end
