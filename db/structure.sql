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
-- Name: evidence_snapshots_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.evidence_snapshots_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'evidence_snapshots are immutable and cannot be updated or deleted';
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
    scoring_strategy_id bigint NOT NULL,
    snapshot_at timestamp(6) without time zone NOT NULL,
    rainfall_24h_mm numeric(8,1) DEFAULT 0.0 NOT NULL,
    historical_event_count integer DEFAULT 0 NOT NULL,
    point_type character varying NOT NULL,
    road_status character varying NOT NULL,
    last_inspected_at timestamp(6) without time zone,
    total_score integer NOT NULL,
    risk_level character varying NOT NULL,
    dispatch_status character varying NOT NULL,
    score_breakdown jsonb NOT NULL,
    explanation jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    business_id character varying
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
    name character varying NOT NULL,
    point_type character varying NOT NULL,
    location character varying,
    road_accessible boolean DEFAULT true NOT NULL,
    road_closed_at timestamp(6) without time zone,
    last_inspected_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    historical_event_count integer DEFAULT 0 NOT NULL,
    latest_rainfall_24h_mm numeric(8,1) DEFAULT 0.0
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
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: scoring_strategies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scoring_strategies (
    id bigint NOT NULL,
    version integer NOT NULL,
    name character varying NOT NULL,
    description text,
    effective_at timestamp(6) without time zone NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    rules jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: scoring_strategies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.scoring_strategies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scoring_strategies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.scoring_strategies_id_seq OWNED BY public.scoring_strategies.id;


--
-- Name: evidence_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_snapshots ALTER COLUMN id SET DEFAULT nextval('public.evidence_snapshots_id_seq'::regclass);


--
-- Name: hazard_points id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_points ALTER COLUMN id SET DEFAULT nextval('public.hazard_points_id_seq'::regclass);


--
-- Name: scoring_strategies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scoring_strategies ALTER COLUMN id SET DEFAULT nextval('public.scoring_strategies_id_seq'::regclass);


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
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: scoring_strategies scoring_strategies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scoring_strategies
    ADD CONSTRAINT scoring_strategies_pkey PRIMARY KEY (id);


--
-- Name: index_evidence_snapshots_for_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_for_queue ON public.evidence_snapshots USING btree (dispatch_status, total_score, id);


--
-- Name: index_evidence_snapshots_on_business_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_evidence_snapshots_on_business_id_unique ON public.evidence_snapshots USING btree (business_id) WHERE (business_id IS NOT NULL);


--
-- Name: index_evidence_snapshots_on_hazard_point_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_on_hazard_point_id ON public.evidence_snapshots USING btree (hazard_point_id);


--
-- Name: index_evidence_snapshots_on_hazard_point_id_and_snapshot_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_on_hazard_point_id_and_snapshot_at ON public.evidence_snapshots USING btree (hazard_point_id, snapshot_at);


--
-- Name: index_evidence_snapshots_on_scoring_strategy_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_on_scoring_strategy_id ON public.evidence_snapshots USING btree (scoring_strategy_id);


--
-- Name: index_evidence_snapshots_on_snapshot_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_on_snapshot_at ON public.evidence_snapshots USING btree (snapshot_at);


--
-- Name: index_evidence_snapshots_on_total_score_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_snapshots_on_total_score_and_id ON public.evidence_snapshots USING btree (total_score, id);


--
-- Name: index_hazard_points_on_historical_event_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hazard_points_on_historical_event_count ON public.hazard_points USING btree (historical_event_count);


--
-- Name: index_hazard_points_on_last_inspected_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hazard_points_on_last_inspected_at ON public.hazard_points USING btree (last_inspected_at);


--
-- Name: index_hazard_points_on_point_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hazard_points_on_point_type ON public.hazard_points USING btree (point_type);


--
-- Name: index_hazard_points_on_road_accessible; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hazard_points_on_road_accessible ON public.hazard_points USING btree (road_accessible);


--
-- Name: index_scoring_strategies_on_published_effective_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_scoring_strategies_on_published_effective_at ON public.scoring_strategies USING btree (effective_at) WHERE ((status)::text = 'published'::text);


--
-- Name: index_scoring_strategies_on_status_and_effective_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scoring_strategies_on_status_and_effective_at ON public.scoring_strategies USING btree (status, effective_at);


--
-- Name: index_scoring_strategies_on_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_scoring_strategies_on_version ON public.scoring_strategies USING btree (version);


--
-- Name: evidence_snapshots evidence_snapshots_no_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER evidence_snapshots_no_delete BEFORE DELETE ON public.evidence_snapshots FOR EACH ROW EXECUTE FUNCTION public.evidence_snapshots_immutable();


--
-- Name: evidence_snapshots evidence_snapshots_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER evidence_snapshots_no_update BEFORE UPDATE ON public.evidence_snapshots FOR EACH ROW EXECUTE FUNCTION public.evidence_snapshots_immutable();


--
-- Name: evidence_snapshots fk_rails_09ba61e4a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_snapshots
    ADD CONSTRAINT fk_rails_09ba61e4a0 FOREIGN KEY (scoring_strategy_id) REFERENCES public.scoring_strategies(id);


--
-- Name: evidence_snapshots fk_rails_98934eae40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_snapshots
    ADD CONSTRAINT fk_rails_98934eae40 FOREIGN KEY (hazard_point_id) REFERENCES public.hazard_points(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260802000005'),
('20260802000004'),
('20260802000003'),
('20260802000002'),
('20260802000001');

