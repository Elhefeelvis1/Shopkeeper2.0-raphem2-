--
-- PostgreSQL database dump
--

\restrict odSCDh3LnchlOAnuJrqEZFvqY47mqGHqllFy5Yv54614xkvrmUr9Q9hzNXwV2b4

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

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
-- Name: create_debt_after_sale(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_debt_after_sale() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO customer_debts (sale_id, customer_id, amount, status)
    VALUES (NEW.id, NEW.customer_id, NEW.total_amount, 'pending');
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_debt_after_sale() OWNER TO postgres;

--
-- Name: create_debt_after_wholesale(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_debt_after_wholesale() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO customer_debts (wholesale_id, customer_id, amount, status)
    VALUES (NEW.id, NEW.customer_id, NEW.total_amount, 'pending');
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_debt_after_wholesale() OWNER TO postgres;

--
-- Name: update_all_stocks_total_quantity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_all_stocks_total_quantity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- For INSERT or UPDATE:
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        UPDATE all_stocks
        SET total_quantity_in_stock = (
            SELECT COALESCE(SUM(quantity_in_lot), 0)
            FROM stock_lots
            WHERE product_id = NEW.product_id
        )
        WHERE id = NEW.product_id;
        RETURN NEW;
    END IF;

    -- For DELETE:
    IF (TG_OP = 'DELETE') THEN
        UPDATE all_stocks
        SET total_quantity_in_stock = (
            SELECT COALESCE(SUM(quantity_in_lot), 0)
            FROM stock_lots
            WHERE product_id = OLD.product_id
        )
        WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;

    RETURN NULL; -- Should not be reached
END;
$$;


ALTER FUNCTION public.update_all_stocks_total_quantity() OWNER TO postgres;

--
-- Name: update_last_cost(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_last_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE all_stocks
    SET last_cost_price = NEW.cost_per_unit
    WHERE id = NEW.product_id;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_last_cost() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: all_stocks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.all_stocks (
    id integer NOT NULL,
    name text NOT NULL,
    generic_name text,
    serial_number text,
    unit_selling_price numeric(10,2) NOT NULL,
    reorder_level integer NOT NULL,
    description text,
    total_quantity_in_stock integer DEFAULT 0 NOT NULL,
    entry_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_updated_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id integer NOT NULL,
    unit_id integer NOT NULL,
    category_id integer DEFAULT 0,
    company_id integer,
    last_cost_price numeric(10,2),
    barcode character varying(50),
    wholesale_price numeric(10,2) DEFAULT 0.00,
    wholesale_multiplier integer DEFAULT 1,
    wholesale_unit_id integer,
    CONSTRAINT all_stocks_total_quantity_in_stock_check CHECK ((total_quantity_in_stock >= 0))
);


ALTER TABLE public.all_stocks OWNER TO postgres;

--
-- Name: all_stocks_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.all_stocks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.all_stocks_id_seq OWNER TO postgres;

--
-- Name: all_stocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.all_stocks_id_seq OWNED BY public.all_stocks.id;


--
-- Name: banks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.banks (
    id integer NOT NULL,
    bank_name character varying(55) NOT NULL,
    account_number bigint
);


ALTER TABLE public.banks OWNER TO postgres;

--
-- Name: banks_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.banks ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.banks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categories (
    id integer NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.categories OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categories_id_seq OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.companies (
    id integer NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.companies OWNER TO postgres;

--
-- Name: companies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.companies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.companies_id_seq OWNER TO postgres;

--
-- Name: companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.companies_id_seq OWNED BY public.companies.id;


--
-- Name: customer_debts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer_debts (
    id integer NOT NULL,
    sale_id integer,
    customer_id integer NOT NULL,
    amount numeric(10,2) NOT NULL,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(25) DEFAULT 'pending'::character varying NOT NULL,
    wholesale_id integer,
    CONSTRAINT chk_customer_debts_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'cleared'::character varying])::text[])))
);


ALTER TABLE public.customer_debts OWNER TO postgres;

--
-- Name: customer_debts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customer_debts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customer_debts_id_seq OWNER TO postgres;

--
-- Name: customer_debts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customer_debts_id_seq OWNED BY public.customer_debts.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    id integer NOT NULL,
    name text NOT NULL,
    phone_number text,
    address text,
    email text,
    customer_notes text
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customers_id_seq OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expenses (
    id integer NOT NULL,
    amount numeric(10,2) NOT NULL,
    description text NOT NULL,
    date date DEFAULT CURRENT_DATE,
    user_id integer
);


ALTER TABLE public.expenses OWNER TO postgres;

--
-- Name: expenses_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.expenses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.expenses_id_seq OWNER TO postgres;

--
-- Name: expenses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.expenses_id_seq OWNED BY public.expenses.id;


--
-- Name: purchase_line_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_line_items (
    id integer NOT NULL,
    product_id integer NOT NULL,
    lot_id integer,
    quantity_purchased integer NOT NULL,
    cost_per_unit numeric(10,2) NOT NULL,
    purchase_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    purchase_id integer
);


ALTER TABLE public.purchase_line_items OWNER TO postgres;

--
-- Name: purchases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchases (
    id integer NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    supplier_id integer,
    user_id integer
);


ALTER TABLE public.purchases OWNER TO postgres;

--
-- Name: purchases_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.purchases_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.purchases_id_seq OWNER TO postgres;

--
-- Name: purchases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.purchases_id_seq OWNED BY public.purchase_line_items.id;


--
-- Name: purchases_id_seq1; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.purchases_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.purchases_id_seq1 OWNER TO postgres;

--
-- Name: purchases_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.purchases_id_seq1 OWNED BY public.purchases.id;


--
-- Name: sale_line_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sale_line_items (
    id integer NOT NULL,
    sale_id integer NOT NULL,
    product_id integer NOT NULL,
    lot_id integer NOT NULL,
    quantity_sold integer NOT NULL,
    selling_price_per_unit numeric(10,2) NOT NULL,
    cost_at_sale numeric(10,2) NOT NULL,
    CONSTRAINT sale_line_items_quantity_sold_check CHECK ((quantity_sold > 0))
);


ALTER TABLE public.sale_line_items OWNER TO postgres;

--
-- Name: sale_line_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sale_line_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sale_line_items_id_seq OWNER TO postgres;

--
-- Name: sale_line_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sale_line_items_id_seq OWNED BY public.sale_line_items.id;


--
-- Name: sales; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales (
    id integer NOT NULL,
    sale_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    customer_id integer,
    user_id integer NOT NULL,
    discount_applied integer,
    pay_route character varying(55) DEFAULT 'Cash'::character varying NOT NULL,
    bank_id integer,
    client_sale_id character varying(100)
);


ALTER TABLE public.sales OWNER TO postgres;

--
-- Name: sales_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sales_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sales_id_seq OWNER TO postgres;

--
-- Name: sales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sales_id_seq OWNED BY public.sales.id;


--
-- Name: stock_changes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_changes (
    id integer NOT NULL,
    product_id integer NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    cost_impact numeric(10,2),
    change_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id integer NOT NULL,
    sale_id integer,
    purchase_id integer,
    lot_id integer,
    old_quantity integer,
    wholesale_id integer
);


ALTER TABLE public.stock_changes OWNER TO postgres;

--
-- Name: stock_changes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stock_changes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stock_changes_id_seq OWNER TO postgres;

--
-- Name: stock_changes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_changes_id_seq OWNED BY public.stock_changes.id;


--
-- Name: stock_lots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_lots (
    lot_id integer NOT NULL,
    product_id integer NOT NULL,
    quantity_in_lot integer NOT NULL,
    cost_per_unit numeric(10,2) NOT NULL,
    expiry_date date,
    entry_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_updated_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    purchase_line_item_id integer,
    is_closed boolean DEFAULT false,
    CONSTRAINT stock_lots_quantity_in_lot_check CHECK ((quantity_in_lot >= 0))
);


ALTER TABLE public.stock_lots OWNER TO postgres;

--
-- Name: stock_lots_lot_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stock_lots_lot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stock_lots_lot_id_seq OWNER TO postgres;

--
-- Name: stock_lots_lot_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_lots_lot_id_seq OWNED BY public.stock_lots.lot_id;


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.suppliers (
    id integer NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.suppliers OWNER TO postgres;

--
-- Name: suppliers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.suppliers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.suppliers_id_seq OWNER TO postgres;

--
-- Name: suppliers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.suppliers_id_seq OWNED BY public.suppliers.id;


--
-- Name: units; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.units (
    id integer NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.units OWNER TO postgres;

--
-- Name: units_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.units_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.units_id_seq OWNER TO postgres;

--
-- Name: units_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.units_id_seq OWNED BY public.units.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username text NOT NULL,
    password text NOT NULL,
    role text NOT NULL,
    theme text DEFAULT 'light'::text,
    permissions jsonb DEFAULT '{"can_audit": false, "can_discount": false, "can_purchase": false, "can_view_wholesale": true}'::jsonb NOT NULL
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: wholesale_line_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wholesale_line_items (
    id integer NOT NULL,
    wholesale_id integer NOT NULL,
    product_id integer NOT NULL,
    lot_id integer,
    quantity_sold numeric(10,3) NOT NULL,
    unit_multiplier integer DEFAULT 1 NOT NULL,
    total_base_units numeric(10,2) NOT NULL,
    selling_price_per_unit numeric(10,2) NOT NULL,
    cost_at_sale numeric(10,2),
    wholesale_unit_id integer
);


ALTER TABLE public.wholesale_line_items OWNER TO postgres;

--
-- Name: wholesale_line_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wholesale_line_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wholesale_line_items_id_seq OWNER TO postgres;

--
-- Name: wholesale_line_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wholesale_line_items_id_seq OWNED BY public.wholesale_line_items.id;


--
-- Name: wholesale_units; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wholesale_units (
    id integer NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE public.wholesale_units OWNER TO postgres;

--
-- Name: wholesale_units_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wholesale_units_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wholesale_units_id_seq OWNER TO postgres;

--
-- Name: wholesale_units_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wholesale_units_id_seq OWNED BY public.wholesale_units.id;


--
-- Name: wholesales; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wholesales (
    id integer NOT NULL,
    wholesale_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    customer_id integer,
    user_id integer NOT NULL,
    discount_applied numeric(10,2) DEFAULT 0.00,
    pay_route character varying(50) DEFAULT 'Cash'::character varying NOT NULL,
    bank_id integer
);


ALTER TABLE public.wholesales OWNER TO postgres;

--
-- Name: wholesales_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wholesales_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wholesales_id_seq OWNER TO postgres;

--
-- Name: wholesales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wholesales_id_seq OWNED BY public.wholesales.id;


--
-- Name: all_stocks id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks ALTER COLUMN id SET DEFAULT nextval('public.all_stocks_id_seq'::regclass);


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: companies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies ALTER COLUMN id SET DEFAULT nextval('public.companies_id_seq'::regclass);


--
-- Name: customer_debts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_debts ALTER COLUMN id SET DEFAULT nextval('public.customer_debts_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: expenses id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses ALTER COLUMN id SET DEFAULT nextval('public.expenses_id_seq'::regclass);


--
-- Name: purchase_line_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_line_items ALTER COLUMN id SET DEFAULT nextval('public.purchases_id_seq'::regclass);


--
-- Name: purchases id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases ALTER COLUMN id SET DEFAULT nextval('public.purchases_id_seq1'::regclass);


--
-- Name: sale_line_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sale_line_items ALTER COLUMN id SET DEFAULT nextval('public.sale_line_items_id_seq'::regclass);


--
-- Name: sales id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales ALTER COLUMN id SET DEFAULT nextval('public.sales_id_seq'::regclass);


--
-- Name: stock_changes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_changes ALTER COLUMN id SET DEFAULT nextval('public.stock_changes_id_seq'::regclass);


--
-- Name: stock_lots lot_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_lots ALTER COLUMN lot_id SET DEFAULT nextval('public.stock_lots_lot_id_seq'::regclass);


--
-- Name: suppliers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers ALTER COLUMN id SET DEFAULT nextval('public.suppliers_id_seq'::regclass);


--
-- Name: units id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units ALTER COLUMN id SET DEFAULT nextval('public.units_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: wholesale_line_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_line_items ALTER COLUMN id SET DEFAULT nextval('public.wholesale_line_items_id_seq'::regclass);


--
-- Name: wholesale_units id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_units ALTER COLUMN id SET DEFAULT nextval('public.wholesale_units_id_seq'::regclass);


--
-- Name: wholesales id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesales ALTER COLUMN id SET DEFAULT nextval('public.wholesales_id_seq'::regclass);


--
-- Name: all_stocks all_stocks_barcode_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT all_stocks_barcode_key UNIQUE (barcode);


--
-- Name: all_stocks all_stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT all_stocks_pkey PRIMARY KEY (id);


--
-- Name: all_stocks all_stocks_serial_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT all_stocks_serial_number_key UNIQUE (serial_number);


--
-- Name: banks banks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.banks
    ADD CONSTRAINT banks_pkey PRIMARY KEY (id);


--
-- Name: categories categories_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_key UNIQUE (name);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: companies companies_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_name_key UNIQUE (name);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: customer_debts customer_debts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT customer_debts_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- Name: purchase_line_items purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_line_items
    ADD CONSTRAINT purchases_pkey PRIMARY KEY (id);


--
-- Name: purchases purchases_pkey1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_pkey1 PRIMARY KEY (id);


--
-- Name: sale_line_items sale_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sale_line_items
    ADD CONSTRAINT sale_line_items_pkey PRIMARY KEY (id);


--
-- Name: sales sales_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_pkey PRIMARY KEY (id);


--
-- Name: stock_changes stock_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_changes
    ADD CONSTRAINT stock_changes_pkey PRIMARY KEY (id);


--
-- Name: stock_lots stock_lots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_lots
    ADD CONSTRAINT stock_lots_pkey PRIMARY KEY (lot_id);


--
-- Name: suppliers suppliers_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_name_key UNIQUE (name);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: customers unique_customer_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT unique_customer_name UNIQUE (name);


--
-- Name: all_stocks unique_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT unique_name UNIQUE (name);


--
-- Name: units units_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_name_key UNIQUE (name);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: wholesale_line_items wholesale_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_line_items
    ADD CONSTRAINT wholesale_line_items_pkey PRIMARY KEY (id);


--
-- Name: wholesale_units wholesale_units_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_units
    ADD CONSTRAINT wholesale_units_name_key UNIQUE (name);


--
-- Name: wholesale_units wholesale_units_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_units
    ADD CONSTRAINT wholesale_units_pkey PRIMARY KEY (id);


--
-- Name: wholesales wholesales_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesales
    ADD CONSTRAINT wholesales_pkey PRIMARY KEY (id);


--
-- Name: idx_sales_client_sale_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_sales_client_sale_id ON public.sales USING btree (client_sale_id) WHERE (client_sale_id IS NOT NULL);


--
-- Name: sales trg_after_sale_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_after_sale_insert AFTER INSERT ON public.sales FOR EACH ROW WHEN (((new.pay_route)::text = 'Credit'::text)) EXECUTE FUNCTION public.create_debt_after_sale();


--
-- Name: wholesales trg_after_wholesale_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_after_wholesale_insert AFTER INSERT ON public.wholesales FOR EACH ROW WHEN ((((new.pay_route)::text = 'Credit'::text) AND (new.customer_id IS NOT NULL))) EXECUTE FUNCTION public.create_debt_after_wholesale();


--
-- Name: stock_lots trg_update_all_stocks_total_on_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_all_stocks_total_on_delete AFTER DELETE ON public.stock_lots FOR EACH ROW EXECUTE FUNCTION public.update_all_stocks_total_quantity();


--
-- Name: stock_lots trg_update_all_stocks_total_on_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_all_stocks_total_on_insert AFTER INSERT ON public.stock_lots FOR EACH ROW EXECUTE FUNCTION public.update_all_stocks_total_quantity();


--
-- Name: stock_lots trg_update_all_stocks_total_on_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_all_stocks_total_on_update AFTER UPDATE OF quantity_in_lot ON public.stock_lots FOR EACH ROW EXECUTE FUNCTION public.update_all_stocks_total_quantity();


--
-- Name: stock_lots trg_update_last_cost; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_last_cost AFTER INSERT ON public.stock_lots FOR EACH ROW EXECUTE FUNCTION public.update_last_cost();


--
-- Name: all_stocks fk_all_stocks_wholesale_unit; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT fk_all_stocks_wholesale_unit FOREIGN KEY (wholesale_unit_id) REFERENCES public.wholesale_units(id) ON DELETE SET NULL;


--
-- Name: all_stocks fk_category_product_def; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT fk_category_product_def FOREIGN KEY (category_id) REFERENCES public.categories(id) ON UPDATE CASCADE ON DELETE SET DEFAULT;


--
-- Name: all_stocks fk_company_product_def; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT fk_company_product_def FOREIGN KEY (company_id) REFERENCES public.companies(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: customer_debts fk_customer; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: customer_debts fk_customer_debts_wholesale; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT fk_customer_debts_wholesale FOREIGN KEY (wholesale_id) REFERENCES public.wholesales(id) ON DELETE SET NULL;


--
-- Name: stock_changes fk_lot_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_changes
    ADD CONSTRAINT fk_lot_id FOREIGN KEY (lot_id) REFERENCES public.stock_lots(lot_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: purchase_line_items fk_lot_purchase; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_line_items
    ADD CONSTRAINT fk_lot_purchase FOREIGN KEY (lot_id) REFERENCES public.stock_lots(lot_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sale_line_items fk_lot_sold; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sale_line_items
    ADD CONSTRAINT fk_lot_sold FOREIGN KEY (lot_id) REFERENCES public.stock_lots(lot_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stock_changes fk_product_change; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_changes
    ADD CONSTRAINT fk_product_change FOREIGN KEY (product_id) REFERENCES public.all_stocks(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stock_lots fk_product_lot; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_lots
    ADD CONSTRAINT fk_product_lot FOREIGN KEY (product_id) REFERENCES public.all_stocks(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: purchase_line_items fk_product_purchase; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_line_items
    ADD CONSTRAINT fk_product_purchase FOREIGN KEY (product_id) REFERENCES public.all_stocks(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sale_line_items fk_product_sold; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sale_line_items
    ADD CONSTRAINT fk_product_sold FOREIGN KEY (product_id) REFERENCES public.all_stocks(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stock_changes fk_purchase_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_changes
    ADD CONSTRAINT fk_purchase_id FOREIGN KEY (purchase_id) REFERENCES public.purchases(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: stock_lots fk_purchase_line_item_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_lots
    ADD CONSTRAINT fk_purchase_line_item_id FOREIGN KEY (purchase_line_item_id) REFERENCES public.purchase_line_items(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: customer_debts fk_sale; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT fk_sale FOREIGN KEY (sale_id) REFERENCES public.sales(id);


--
-- Name: sale_line_items fk_sale_header; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sale_line_items
    ADD CONSTRAINT fk_sale_header FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: stock_changes fk_sale_transaction; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_changes
    ADD CONSTRAINT fk_sale_transaction FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE SET NULL;


--
-- Name: all_stocks fk_unit_product_def; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT fk_unit_product_def FOREIGN KEY (unit_id) REFERENCES public.units(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stock_changes fk_user_change; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_changes
    ADD CONSTRAINT fk_user_change FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: expenses fk_user_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: all_stocks fk_user_product_def; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.all_stocks
    ADD CONSTRAINT fk_user_product_def FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sales fk_user_sale; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_user_sale FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: purchases fk_users_names; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT fk_users_names FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: wholesale_line_items fk_wholesale_line_items_lot; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_line_items
    ADD CONSTRAINT fk_wholesale_line_items_lot FOREIGN KEY (lot_id) REFERENCES public.stock_lots(lot_id) ON DELETE SET NULL;


--
-- Name: wholesale_line_items fk_wholesale_line_items_product; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_line_items
    ADD CONSTRAINT fk_wholesale_line_items_product FOREIGN KEY (product_id) REFERENCES public.all_stocks(id);


--
-- Name: wholesale_line_items fk_wholesale_line_items_wholesale; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_line_items
    ADD CONSTRAINT fk_wholesale_line_items_wholesale FOREIGN KEY (wholesale_id) REFERENCES public.wholesales(id) ON DELETE CASCADE;


--
-- Name: wholesale_line_items fk_wholesale_line_items_wholesale_unit; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesale_line_items
    ADD CONSTRAINT fk_wholesale_line_items_wholesale_unit FOREIGN KEY (wholesale_unit_id) REFERENCES public.wholesale_units(id) ON DELETE SET NULL;


--
-- Name: wholesales fk_wholesales_bank; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesales
    ADD CONSTRAINT fk_wholesales_bank FOREIGN KEY (bank_id) REFERENCES public.banks(id) ON DELETE SET NULL;


--
-- Name: wholesales fk_wholesales_customer; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesales
    ADD CONSTRAINT fk_wholesales_customer FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;


--
-- Name: wholesales fk_wholesales_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wholesales
    ADD CONSTRAINT fk_wholesales_user FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: purchase_line_items purchase_line_items_purchase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_line_items
    ADD CONSTRAINT purchase_line_items_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES public.purchases(id);


--
-- Name: sales sales_bank_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_bank_id_fkey FOREIGN KEY (bank_id) REFERENCES public.banks(id);


--
-- PostgreSQL database dump complete
--

\unrestrict odSCDh3LnchlOAnuJrqEZFvqY47mqGHqllFy5Yv54614xkvrmUr9Q9hzNXwV2b4

