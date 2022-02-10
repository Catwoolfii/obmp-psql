-- -----------------------------------------------------------------------
-- Copyright (c) 2022 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2022 Tim Evens (tim@evensweb.com).  All rights reserved.
-- -----------------------------------------------------------------------

--
-- Table structure for l3vpn rib
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/--
DROP TABLE IF EXISTS l3vpn_rib CASCADE;
CREATE TABLE l3vpn_rib (
	                       hash_id                 uuid                NOT NULL,
	                       base_attr_hash_id       uuid,
	                       peer_hash_id            uuid                NOT NULL,
	                       isIPv4                  boolean             NOT NULL,
	                       rd                      varchar(128)        NOT NULL,
	                       origin_as               bigint,
	                       prefix                  inet                NOT NULL,
	                       prefix_len              smallint            NOT NULL,
	                       timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	                       first_added_timestamp   timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	                       isWithdrawn             boolean             NOT NULL DEFAULT false,
	                       path_id                 bigint,
	                       labels                  varchar(255),
	                       ext_community_list      varchar(50)[],
	                       isPrePolicy             boolean             NOT NULL DEFAULT true,
	                       isAdjRibIn              boolean             NOT NULL DEFAULT true,
	                       PRIMARY KEY (peer_hash_id, hash_id)
);

CREATE INDEX ON l3vpn_rib (hash_id);
CREATE INDEX ON l3vpn_rib (timestamp);
CREATE INDEX ON l3vpn_rib (rd);
CREATE INDEX ON l3vpn_rib (base_attr_hash_id);
CREATE INDEX ON l3vpn_rib USING GIST (prefix inet_ops);
CREATE INDEX ON l3vpn_rib USING GIN  (ext_community_list array_ops);
CREATE INDEX ON l3vpn_rib (origin_as);
CREATE INDEX ON l3vpn_rib (peer_hash_id,origin_as);

-- Table structure for table ip_rib_log
DROP TABLE IF EXISTS l3vpn_rib_log CASCADE;
CREATE TABLE l3vpn_rib_log (
	                           id                      bigserial           NOT NULL,
	                           base_attr_hash_id       uuid                ,
	                           timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	                           rd                      varchar(128)        NOT NULL,
	                           peer_hash_id            uuid                NOT NULL,
	                           prefix                  inet                NOT NULL,
	                           prefix_len              smallint            NOT NULL,
	                           origin_as               bigint              NOT NULL,
	                           ext_community_list      varchar(50)[],
	                           isPrePolicy             boolean             NOT NULL DEFAULT true,
	                           isAdjRibIn              boolean             NOT NULL DEFAULT true,
	                           isWithdrawn             boolean             NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON l3vpn_rib_log USING GIST (prefix inet_ops);
CREATE INDEX ON l3vpn_rib_log USING GIN  (ext_community_list array_ops);
CREATE INDEX ON l3vpn_rib_log (rd);
CREATE INDEX ON l3vpn_rib_log (origin_as);
CREATE INDEX ON l3vpn_rib_log (peer_hash_id);
CREATE INDEX ON l3vpn_rib_log (base_attr_hash_id);
CREATE INDEX ON l3vpn_rib_log (peer_hash_id,base_attr_hash_id);

-- ALTER TABLE l3vpn_rib_log SET (
-- 	timescaledb.compress,
-- 	timescaledb.compress_segmentby = 'peer_hash_id,prefix,origin_as'
-- 	);
-- SELECT add_compression_policy('l3vpn_rib_log', INTERVAL '2 days');

SELECT create_hypertable('l3vpn_rib_log', 'timestamp', chunk_time_interval => interval '1 hours');
SELECT add_retention_policy('l3vpn_rib_log', INTERVAL '3 months');


--
-- L3VPN Views
--
drop view IF EXISTS v_l3vpn_routes CASCADE;
CREATE  VIEW v_l3vpn_routes AS
SELECT  CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
        CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
        r.rd,r.prefix AS Prefix,r.prefix_len AS PrefixLen,
        attr.origin AS Origin,r.origin_as AS Origin_AS,attr.med AS MED,
        attr.local_pref AS LocalPref,attr.next_hop AS NH,attr.as_path AS AS_Path,
        attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
        r.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
        attr.cluster_list AS ClusterList,
        attr.aggregator AS Aggregator,p.peer_addr AS PeerAddress, p.peer_as AS PeerASN,r.isIPv4 as isIPv4,
        p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
        r.timestamp AS LastModified, r.first_added_timestamp as FirstAddedTimestamp,
        r.path_id, r.labels,
        r.hash_id as rib_hash_id,
        r.base_attr_hash_id as base_hash_id, r.peer_hash_id, rtr.hash_id as router_hash_id,r.isWithdrawn,
        r.isPrePolicy,r.isAdjRibIn
FROM l3vpn_rib r
	     JOIN bgp_peers p ON (r.peer_hash_id = p.hash_id)
	     JOIN base_attrs attr ON (attr.hash_id = r.base_attr_hash_id and attr.peer_hash_id = r.peer_hash_id)
	     JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);


---
--- L3VPN Triggers
---
CREATE OR REPLACE FUNCTION t_l3vpn_rib_update()
	RETURNS trigger AS $$
BEGIN
	IF (new.isWithdrawn) THEN
		INSERT INTO l3vpn_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp,
		                           rd,ext_community_list)
		VALUES (true,new.prefix,new.prefix_len,old.base_attr_hash_id,new.peer_hash_id,
		        old.origin_as,new.timestamp,old.rd,old.ext_community_list);
	ELSE
		INSERT INTO l3vpn_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp,
		                           rd,ext_community_list)
		VALUES (false,new.prefix,new.prefix_len,new.base_attr_hash_id,new.peer_hash_id,
		        new.origin_as,new.timestamp,new.rd,new.ext_community_list);
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS upd_l3vpn_rib ON l3vpn_rib;
CREATE TRIGGER upd_l3vpn_rib AFTER UPDATE ON l3vpn_rib
	FOR EACH ROW
	WHEN ((new.isWithdrawn <> old.isWithdrawn) OR
	      (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id))
EXECUTE PROCEDURE t_l3vpn_rib_update();

