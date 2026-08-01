SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: evidence_snapshots_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.evidence_snapshots_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'evidence_snapshots are immutable: % is not allowed', TG_OP
    USING ERRCODE = 'raise_exception';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: evidence_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evidence_snapshots (
    id bigint NOT NULL,
    hazard_point_id bigint NOT NULL,
    rainfall_24h_mm numeric(7,1) NOT NULL,
    historical_event_count integer DEFAULT 0 NOT NULL,
    last_inspected_at timestamp(6) without time zone,
    road_accessible boolean DEFAULT true NOT NULL,
    captured_at timestamp(6) without time zone NOT NULL,
    note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    client_reference character varying
);


--
-- Name: evidence_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.evidence_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: evidence_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.evidence_snapshots_id_seq OWNED BY public.evidence_snapshots.id;


--
-- Name: hazard_points; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_points (
    id bigint NOT NULL,
    external_code character varying NOT NULL,
    name character varying NOT NULL,
    kind character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: hazard_points_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hazard_points_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hazard_points_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hazard_points_id_seq OWNED BY public.hazard_points.id;


--
-- Name: queue_snapshot_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queue_snapshot_entries (
    id bigint NOT NULL,
    queue_snapshot_id bigint NOT NULL,
    score_record_id bigint NOT NULL
);


--
-- Name: queue_snapshot_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.queue_snapshot_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: queue_snapshot_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.queue_snapshot_entries_id_seq OWNED BY public.queue_snapshot_entries.id;


--
-- Name: queue_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queue_snapshots (
    id bigint NOT NULL,
    name character varying NOT NULL,
    strategy_version_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: queue_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.queue_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: queue_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.queue_snapshots_id_seq OWNED BY public.queue_snapshots.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: score_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.score_records (
    id bigint NOT NULL,
    hazard_point_id bigint NOT NULL,
    evidence_snapshot_id bigint NOT NULL,
    strategy_version_id bigint NOT NULL,
    components jsonb NOT NULL,
    total_score integer NOT NULL,
    risk_level character varying NOT NULL,
    scheduling_status character varying NOT NULL,
    is_current boolean DEFAULT true NOT NULL,
    computed_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT score_records_risk_level_check CHECK (((risk_level)::text = ANY ((ARRAY['high'::character varying, 'medium'::character varying, 'low'::character varying])::text[]))),
    CONSTRAINT score_records_scheduling_status_check CHECK (((scheduling_status)::text = ANY ((ARRAY['schedulable'::character varying, 'blocked'::character varying])::text[])))
);


--
-- Name: score_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.score_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: score_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.score_records_id_seq OWNED BY public.score_records.id;


--
-- Name: strategy_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strategy_versions (
    id bigint NOT NULL,
    version integer NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    effective_range tstzrange NOT NULL,
    rules jsonb NOT NULL,
    published_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT strategy_versions_status_check CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'published'::character varying, 'retired'::character varying])::text[])))
);


--
-- Name: strategy_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.strategy_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: strategy_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.strategy_versions_id_seq OWNED BY public.strategy_versions.id;


--
-- Name: evidence_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_snapshots ALTER COLUMN id SET DEFAULT nextval('public.evidence_snapshots_id_seq'::regclass);


--
-- Name: hazard_points id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_points ALTER COLUMN id SET DEFAULT nextval('public.hazard_points_id_seq'::regclass);


--
-- Name: queue_snapshot_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_snapshot_entries ALTER COLUMN id SET DEFAULT nextval('public.queue_snapshot_entries_id_seq'::regclass);


--
-- Name: queue_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_snapshots ALTER COLUMN id SET DEFAULT nextval('public.queue_snapshots_id_seq'::regclass);


--
-- Name: score_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.score_records ALTER COLUMN id SET DEFAULT nextval('public.score_records_id_seq'::regclass);


--
-- Name: strategy_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_versions ALTER COLUMN id SET DEFAULT nextval('public.strategy_versions_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: evidence_snapshots evidence_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_snapshots
    ADD CONSTRAINT evidence_snapshots_pkey PRIMARY KEY (id);


--
-- Name: hazard_points hazard_points_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_points
    ADD CONSTRAINT hazard_points_pkey PRIMARY KEY (id);


--
-- Name: queue_snapshot_entries queue_snapshot_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_snapshot_entries
    ADD CONSTRAINT queue_snapshot_entries_pkey PRIMARY KEY (id);


--
-- Name: queue_snapshots queue_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_snapshots
    ADD CONSTRAINT queue_snapshots_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: score_records score_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.score_records
    ADD CONSTRAINT score_records_pkey PRIMARY KEY (id);


--
-- Name: strategy_versions strategy_versions_no_published_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_versions
    ADD CONSTRAINT strategy_versions_no_published_overlap EXCLUDE USING gist (effective_range WITH &&) WHERE (((status)::text = 'published'::text));


--
-- Name: strategy_versions strategy_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strategy_versions
    ADD CONSTRAINT strategy_versions_pkey PRIMARY KEY (id);


--
-- Name: idx_queue_snapshot_entries_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_queue_snapshot_entries_unique ON public.queue_snapshot_entries USING btree (queue_snapshot_id, score_record_id);


--
-- Name: idx_score_records_current_per_point; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_score_records_current_per_point ON public.score_records USING btree (hazard_point_id) WHERE is_current;


--
-- Name: idx_score_records_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_score_records_queue ON public.score_records USING btree (total_score DESC, id) WHERE is_current;


--
-- Name: idx_score_records_snapshot_strategy; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_score_records_snapshot_strategy ON public.score_records USING btree (evidence_snapshot_id, strategy_version_id);


--
-- Name: index_evidence_snapshots_on_client_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_evidence_snapshots_on_client_reference ON public.evidence_snapshots USING btree (client_reference);


--
-- Name: index_evidence_snapshots_on_hazard_point_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_on_hazard_point_id ON public.evidence_snapshots USING btree (hazard_point_id);


--
-- Name: index_evidence_snapshots_on_hazard_point_id_and_captured_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_on_hazard_point_id_and_captured_at ON public.evidence_snapshots USING btree (hazard_point_id, captured_at);


--
-- Name: index_hazard_points_on_external_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_hazard_points_on_external_code ON public.hazard_points USING btree (external_code);


--
-- Name: index_queue_snapshot_entries_on_queue_snapshot_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_queue_snapshot_entries_on_queue_snapshot_id ON public.queue_snapshot_entries USING btree (queue_snapshot_id);


--
-- Name: index_queue_snapshot_entries_on_score_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_queue_snapshot_entries_on_score_record_id ON public.queue_snapshot_entries USING btree (score_record_id);


--
-- Name: index_queue_snapshots_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_queue_snapshots_on_name ON public.queue_snapshots USING btree (name);


--
-- Name: index_queue_snapshots_on_strategy_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_queue_snapshots_on_strategy_version_id ON public.queue_snapshots USING btree (strategy_version_id);


--
-- Name: index_score_records_on_evidence_snapshot_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_score_records_on_evidence_snapshot_id ON public.score_records USING btree (evidence_snapshot_id);


--
-- Name: index_score_records_on_hazard_point_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_score_records_on_hazard_point_id ON public.score_records USING btree (hazard_point_id);


--
-- Name: index_score_records_on_strategy_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_score_records_on_strategy_version_id ON public.score_records USING btree (strategy_version_id);


--
-- Name: index_strategy_versions_on_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_strategy_versions_on_version ON public.strategy_versions USING btree (version);


--
-- Name: evidence_snapshots evidence_snapshots_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER evidence_snapshots_no_update BEFORE DELETE OR UPDATE ON public.evidence_snapshots FOR EACH ROW EXECUTE FUNCTION public.evidence_snapshots_immutable();


--
-- Name: queue_snapshots fk_rails_295f9cbb5e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_snapshots
    ADD CONSTRAINT fk_rails_295f9cbb5e FOREIGN KEY (strategy_version_id) REFERENCES public.strategy_versions(id);


--
-- Name: queue_snapshot_entries fk_rails_4da19adcda; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_snapshot_entries
    ADD CONSTRAINT fk_rails_4da19adcda FOREIGN KEY (queue_snapshot_id) REFERENCES public.queue_snapshots(id);


--
-- Name: queue_snapshot_entries fk_rails_51f988081a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queue_snapshot_entries
    ADD CONSTRAINT fk_rails_51f988081a FOREIGN KEY (score_record_id) REFERENCES public.score_records(id);


--
-- Name: score_records fk_rails_72a621c16c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.score_records
    ADD CONSTRAINT fk_rails_72a621c16c FOREIGN KEY (hazard_point_id) REFERENCES public.hazard_points(id);


--
-- Name: evidence_snapshots fk_rails_98934eae40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_snapshots
    ADD CONSTRAINT fk_rails_98934eae40 FOREIGN KEY (hazard_point_id) REFERENCES public.hazard_points(id);


--
-- Name: score_records fk_rails_c87fc3b5f4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.score_records
    ADD CONSTRAINT fk_rails_c87fc3b5f4 FOREIGN KEY (evidence_snapshot_id) REFERENCES public.evidence_snapshots(id);


--
-- Name: score_records fk_rails_f743df7eea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.score_records
    ADD CONSTRAINT fk_rails_f743df7eea FOREIGN KEY (strategy_version_id) REFERENCES public.strategy_versions(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260802000000'),
('20260801120000'),
('20260801000004'),
('20260801000003'),
('20260801000002'),
('20260801000001');

