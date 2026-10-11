# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Geospatial commands.
    module Geo
      # +entries+ is a flat [lon, lat, member, ...] list, or an Array of
      # [lon, lat, member] triples.
      def geoadd(key, entries, nx: false, xx: false, ch: false)
        args = ["GEOADD", key]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("CH") if ch
        args.concat(finite_geo_entries(entries.flatten))
        invoke(*args)
      end

      # -> Array of [lon, lat] Float pairs (nil for a member not found).
      def geopos(key, *members)
        invoke("GEOPOS", key, *members.flatten) { |r| r.map { |p| p.nil? ? nil : p.map { |v| Wire.parse_float(v) } } }
      end

      def geodist(key, member1, member2, unit: "m")
        invoke("GEODIST", key, member1, member2, unit) { |r| r.nil? ? nil : Wire.parse_float(r) }
      end

      def geohash(key, *members)
        invoke("GEOHASH", key, *members.flatten)
      end

      # Exactly one of :member or :lonlat (a [lon, lat] pair) selects the
      # search center; exactly one of :radius (a [radius, unit] pair) or
      # :box (a [width, height, unit] triple) selects the search area.
      def geosearch(key, member: nil, lonlat: nil, radius: nil, box: nil, asc: nil, desc: nil, count: nil,
                    any: false, withcoord: false, withdist: false, withhash: false)
        args = ["GEOSEARCH", key]
        args.concat(geosearch_origin(member, lonlat))
        args.concat(geosearch_area(radius, box))
        args.push("ASC") if asc
        args.push("DESC") if desc
        if count
          args.push("COUNT", count)
          args.push("ANY") if any
        end
        args.push("WITHCOORD") if withcoord
        args.push("WITHDIST") if withdist
        args.push("WITHHASH") if withhash
        invoke(*args) { |r| geosearch_result(r, withcoord, withdist, withhash) }
      end

      def geosearchstore(destination, source, member: nil, lonlat: nil, radius: nil, box: nil, count: nil,
                         any: false, storedist: false)
        args = ["GEOSEARCHSTORE", destination, source]
        args.concat(geosearch_origin(member, lonlat))
        args.concat(geosearch_area(radius, box))
        if count
          args.push("COUNT", count)
          args.push("ANY") if any
        end
        args.push("STOREDIST") if storedist
        invoke(*args)
      end

      # Deprecated GEORADIUS: members within +radius+ (+unit+ m/km/ft/mi) of
      # a longitude/latitude. Options as #geosearch plus :store/:storedist
      # (destination key; then the reply is the stored count).
      def georadius(key, lon, lat, radius, unit, store: nil, storedist: nil, **opts)
        args = ["GEORADIUS", key, Wire.finite(lon), Wire.finite(lat), Wire.finite(radius), unit]
        georadius_run(args, opts, store, storedist)
      end

      # Read-only GEORADIUS.
      def georadius_ro(key, lon, lat, radius, unit, **opts)
        args = ["GEORADIUS_RO", key, Wire.finite(lon), Wire.finite(lat), Wire.finite(radius), unit]
        georadius_run(args, opts, nil, nil)
      end

      # Deprecated GEORADIUSBYMEMBER: like #georadius around an existing member.
      def georadiusbymember(key, member, radius, unit, store: nil, storedist: nil, **opts)
        args = ["GEORADIUSBYMEMBER", key, member, Wire.finite(radius), unit]
        georadius_run(args, opts, store, storedist)
      end

      # Read-only GEORADIUSBYMEMBER.
      def georadiusbymember_ro(key, member, radius, unit, **opts)
        args = ["GEORADIUSBYMEMBER_RO", key, member, Wire.finite(radius), unit]
        georadius_run(args, opts, nil, nil)
      end

      private

      def georadius_run(args, opts, store, storedist)
        unknown = opts.keys - %i[withcoord withdist withhash count any asc desc]
        raise Error::ArgumentError, "unknown georadius option(s): #{unknown.join(', ')}" unless unknown.empty?

        args.push("WITHCOORD") if opts[:withcoord]
        args.push("WITHDIST") if opts[:withdist]
        args.push("WITHHASH") if opts[:withhash]
        if opts[:count]
          args.push("COUNT", opts[:count])
          args.push("ANY") if opts[:any]
        end
        args.push("ASC") if opts[:asc]
        args.push("DESC") if opts[:desc]
        args.push("STORE", store) if store
        args.push("STOREDIST", storedist) if storedist
        withcoord, withdist, withhash = opts.values_at(:withcoord, :withdist, :withhash)
        invoke(*args) { |r| (store || storedist) ? r : geosearch_result(r, withcoord, withdist, withhash) }
      end

      # Longitude and latitude must be finite numbers; the member name that
      # follows each pair is left alone.
      def finite_geo_entries(flat)
        flat.each_with_index.map { |v, i| (i % 3) == 2 ? v : Wire.finite(v) }
      end

      def geosearch_origin(member, lonlat)
        return ["FROMMEMBER", member] if member
        return ["FROMLONLAT", Wire.finite(lonlat[0]), Wire.finite(lonlat[1])] if lonlat

        raise Error::ArgumentError, "geosearch needs :member or :lonlat"
      end

      def geosearch_area(radius, box)
        return ["BYRADIUS", Wire.finite(radius[0]), radius[1]] if radius
        return ["BYBOX", Wire.finite(box[0]), Wire.finite(box[1]), box[2]] if box

        raise Error::ArgumentError, "geosearch needs :radius or :box"
      end

      def geosearch_result(reply, withcoord, withdist, withhash)
        return reply unless withcoord || withdist || withhash

        reply.map do |row|
          row = Array(row)
          entry = { member: row.shift }
          entry[:dist] = Wire.parse_float(row.shift) if withdist
          entry[:hash] = Integer(row.shift) if withhash
          entry[:coord] = row.shift.map { |v| Wire.parse_float(v) } if withcoord
          entry
        end
      end
    end
  end
end
