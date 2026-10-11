# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Publishing and Pub/Sub introspection. Subscribing is not here: it needs
    # a connection of its own, see Client#subscribe.
    module Publishing
      # Publishes +message+ to +channel+. Returns the number of subscribers
      # that received it.
      def publish(channel, message)
        invoke("PUBLISH", channel, message)
      end

      # Publishes +message+ to a shard channel (SPUBLISH).
      def spublish(channel, message)
        invoke("SPUBLISH", channel, message)
      end

      # Active channels, optionally only those matching the glob +pattern+.
      def pubsub_channels(pattern = nil)
        pattern.nil? ? invoke("PUBSUB", "CHANNELS") : invoke("PUBSUB", "CHANNELS", pattern)
      end

      # Hash of channel => subscriber count for the given channels.
      def pubsub_numsub(*channels)
        invoke("PUBSUB", "NUMSUB", *channels.flatten) { |r| r.is_a?(Hash) ? r : r.each_slice(2).to_h }
      end

      # Number of pattern subscriptions.
      def pubsub_numpat
        invoke("PUBSUB", "NUMPAT")
      end

      # Active shard channels, optionally only those matching +pattern+.
      def pubsub_shardchannels(pattern = nil)
        pattern.nil? ? invoke("PUBSUB", "SHARDCHANNELS") : invoke("PUBSUB", "SHARDCHANNELS", pattern)
      end

      # Hash of shard channel => subscriber count.
      def pubsub_shardnumsub(*channels)
        invoke("PUBSUB", "SHARDNUMSUB", *channels.flatten) { |r| r.is_a?(Hash) ? r : r.each_slice(2).to_h }
      end
    end
  end
end
