# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # Yielded by HotKV::Client#subscribe, #psubscribe and #ssubscribe. Register
  # callbacks for the frames a subscription connection receives; the
  # subscribe family methods also double as a way to change the
  # subscription while the loop is running, when called with channel/pattern
  # arguments and no block:
  #
  #   client.subscribe("news") do |on|
  #     on.message { |channel, payload| puts "#{channel}: #{payload}" }
  #     on.subscribe { |channel, total| puts "listening on #{channel}" }
  #   end
  #
  #   client.subscribe("news") do |on|
  #     on.message do |channel, payload|
  #       on.unsubscribe if payload == "stop" # ends the loop once confirmed
  #     end
  #   end
  class PubSub
    CALLBACK_KINDS = %i[message pmessage smessage subscribe unsubscribe psubscribe punsubscribe ssubscribe
                         sunsubscribe].freeze
    COMMAND_KINDS = %i[subscribe unsubscribe psubscribe punsubscribe ssubscribe sunsubscribe].freeze

    def initialize
      @callbacks = Hash.new { |h, k| h[k] = [] }
      @connection = nil
    end

    def bind(connection)
      @connection = connection
      self
    end

    def dispatch(kind, *args)
      @callbacks[kind].each { |cb| cb.call(*args) }
    end

    CALLBACK_KINDS.each do |kind|
      define_method(kind) do |*args, &block|
        if block
          @callbacks[kind] << block
          self
        elsif COMMAND_KINDS.include?(kind)
          send_wire(kind, args)
        else
          raise Error::ArgumentError, "#{kind} needs a block to register a callback"
        end
      end
    end

    private

    def send_wire(kind, targets)
      @connection.write_command(targets.empty? ? [kind.to_s.upcase] : [kind.to_s.upcase, *targets])
      nil
    end
  end
end
