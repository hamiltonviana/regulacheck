-- ============================================================
-- RegulaCHECK - Schema SQL para Supabase
-- MVP: SaaS de monitoramento de regulamentações brasileiras
-- (Anvisa, ABNT, ISO, DOU)
-- ============================================================

-- ============================================================
-- 1. EXTENSÕES
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 2. TIPOS ENUMERADOS
-- ============================================================
CREATE TYPE subscription_plan AS ENUM ('free', 'starter', 'professional');
CREATE TYPE subscription_status AS ENUM ('active', 'cancelled', 'expired', 'past_due');
CREATE TYPE search_status AS ENUM ('pending', 'processing', 'completed', 'failed');
CREATE TYPE audit_action AS ENUM (
  'user_login',
  'user_logout',
  'user_register',
  'search_created',
  'search_completed',
  'search_failed',
  'subscription_created',
  'subscription_upgraded',
  'subscription_cancelled',
  'extra_search_purchased'
);

-- ============================================================
-- 3. TABELA: plans (catálogo de planos disponíveis)
-- ============================================================
CREATE TABLE public.plans (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          subscription_plan NOT NULL UNIQUE,
  display_name  TEXT NOT NULL,
  description   TEXT,
  monthly_searches INTEGER NOT NULL DEFAULT 0,
  price_monthly NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  extra_search_price NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  max_keywords_per_search INTEGER NOT NULL DEFAULT 5,
  features      JSONB DEFAULT '[]'::jsonb,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 4. TABELA: users (perfil do usuário, vinculada ao auth.users)
-- ============================================================
CREATE TABLE public.users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email           TEXT NOT NULL,
  full_name       TEXT,
  company         TEXT,
  phone           TEXT,
  avatar_url      TEXT,
  role            TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
  is_active       BOOLEAN NOT NULL DEFAULT true,
  onboarding_done BOOLEAN NOT NULL DEFAULT false,
  metadata        JSONB DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 5. TABELA: subscriptions (assinaturas dos usuários)
-- ============================================================
CREATE TABLE public.subscriptions (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  plan_id             UUID NOT NULL REFERENCES public.plans(id),
  status              subscription_status NOT NULL DEFAULT 'active',
  current_period_start TIMESTAMPTZ NOT NULL DEFAULT date_trunc('month', now()),
  current_period_end  TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('month', now()) + INTERVAL '1 month'),
  searches_used       INTEGER NOT NULL DEFAULT 0,
  extra_searches_purchased INTEGER NOT NULL DEFAULT 0,
  stripe_customer_id  TEXT,
  stripe_subscription_id TEXT,
  cancelled_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_active_subscription UNIQUE (user_id, status)
);

-- Índice para busca rápida por usuário
CREATE INDEX idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON public.subscriptions(status);

-- ============================================================
-- 6. TABELA: searches (histórico de buscas)
-- ============================================================
CREATE TABLE public.searches (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  keywords        TEXT[] NOT NULL CHECK (array_length(keywords, 1) BETWEEN 1 AND 5),
  date_start      DATE NOT NULL,
  date_end        DATE NOT NULL,
  sources         TEXT[] DEFAULT ARRAY['anvisa', 'abnt', 'iso', 'dou'],
  status          search_status NOT NULL DEFAULT 'pending',
  results_count   INTEGER NOT NULL DEFAULT 0,
  error_message   TEXT,
  processing_time_ms INTEGER,
  is_extra_search BOOLEAN NOT NULL DEFAULT false,
  metadata        JSONB DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT valid_date_range CHECK (date_end >= date_start)
);

CREATE INDEX idx_searches_user_id ON public.searches(user_id);
CREATE INDEX idx_searches_status ON public.searches(status);
CREATE INDEX idx_searches_created_at ON public.searches(created_at DESC);

-- ============================================================
-- 7. TABELA: results (resultados vinculados à busca)
-- ============================================================
CREATE TABLE public.results (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  search_id       UUID NOT NULL REFERENCES public.searches(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source          TEXT NOT NULL CHECK (source IN ('anvisa', 'abnt', 'iso', 'dou', 'outro')),
  title           TEXT NOT NULL,
  summary         TEXT,
  document_number TEXT,
  document_type   TEXT,
  publication_date DATE,
  url             TEXT,
  relevance_score NUMERIC(3,2) DEFAULT 0.00,
  matched_keywords TEXT[],
  raw_data        JSONB DEFAULT '{}'::jsonb,
  is_read         BOOLEAN NOT NULL DEFAULT false,
  is_bookmarked   BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_results_search_id ON public.results(search_id);
CREATE INDEX idx_results_user_id ON public.results(user_id);
CREATE INDEX idx_results_source ON public.results(source);
CREATE INDEX idx_results_publication_date ON public.results(publication_date DESC);

-- ============================================================
-- 8. TABELA: audit_logs (log de ações)
-- ============================================================
CREATE TABLE public.audit_logs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES public.users(id) ON DELETE SET NULL,
  action      audit_action NOT NULL,
  entity_type TEXT,
  entity_id   UUID,
  details     JSONB DEFAULT '{}'::jsonb,
  ip_address  INET,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX idx_audit_logs_created_at ON public.audit_logs(created_at DESC);

-- ============================================================
-- 9. FUNÇÕES DE ATUALIZAÇÃO AUTOMÁTICA DE updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_users_updated
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER on_subscriptions_updated
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER on_searches_updated
  BEFORE UPDATE ON public.searches
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER on_plans_updated
  BEFORE UPDATE ON public.plans
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================
-- 10. FUNÇÃO: Criar perfil de usuário automaticamente no signup
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  free_plan_id UUID;
BEGIN
  -- Buscar o plano free
  SELECT id INTO free_plan_id FROM public.plans WHERE name = 'free' LIMIT 1;

  -- Criar perfil do usuário
  INSERT INTO public.users (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email)
  );

  -- Criar assinatura free automaticamente
  INSERT INTO public.subscriptions (user_id, plan_id, status)
  VALUES (NEW.id, free_plan_id, 'active');

  -- Registrar no audit log
  INSERT INTO public.audit_logs (user_id, action, details)
  VALUES (NEW.id, 'user_register', jsonb_build_object('email', NEW.email));

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger para criar perfil no signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 11. FUNÇÃO: Verificar limite de consultas do usuário
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_search_limit(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_plan_name subscription_plan;
  v_monthly_limit INTEGER;
  v_searches_used INTEGER;
  v_extra_purchased INTEGER;
  v_total_available INTEGER;
  v_remaining INTEGER;
  v_can_search BOOLEAN;
  v_subscription_id UUID;
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
BEGIN
  -- Buscar assinatura ativa do usuário
  SELECT
    s.id,
    p.name,
    p.monthly_searches,
    s.searches_used,
    s.extra_searches_purchased,
    s.current_period_start,
    s.current_period_end
  INTO
    v_subscription_id,
    v_plan_name,
    v_monthly_limit,
    v_searches_used,
    v_extra_purchased,
    v_period_start,
    v_period_end
  FROM public.subscriptions s
  JOIN public.plans p ON s.plan_id = p.id
  WHERE s.user_id = p_user_id
    AND s.status = 'active'
  ORDER BY s.created_at DESC
  LIMIT 1;

  -- Se não encontrou assinatura
  IF v_subscription_id IS NULL THEN
    RETURN jsonb_build_object(
      'can_search', false,
      'error', 'Nenhuma assinatura ativa encontrada',
      'remaining', 0,
      'total_available', 0,
      'searches_used', 0
    );
  END IF;

  -- Verificar se o período expirou e resetar contador
  IF now() > v_period_end THEN
    UPDATE public.subscriptions
    SET
      searches_used = 0,
      extra_searches_purchased = 0,
      current_period_start = date_trunc('month', now()),
      current_period_end = date_trunc('month', now()) + INTERVAL '1 month'
    WHERE id = v_subscription_id;

    v_searches_used := 0;
    v_extra_purchased := 0;
  END IF;

  -- Calcular disponibilidade
  v_total_available := v_monthly_limit + v_extra_purchased;
  v_remaining := v_total_available - v_searches_used;
  v_can_search := v_remaining > 0;

  RETURN jsonb_build_object(
    'can_search', v_can_search,
    'plan', v_plan_name,
    'monthly_limit', v_monthly_limit,
    'searches_used', v_searches_used,
    'extra_purchased', v_extra_purchased,
    'total_available', v_total_available,
    'remaining', v_remaining,
    'period_start', v_period_start,
    'period_end', v_period_end,
    'subscription_id', v_subscription_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 12. FUNÇÃO: Incrementar contador de buscas
-- ============================================================
CREATE OR REPLACE FUNCTION public.increment_search_count(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_limit_info JSONB;
  v_subscription_id UUID;
  v_is_extra BOOLEAN;
  v_monthly_limit INTEGER;
  v_searches_used INTEGER;
BEGIN
  -- Verificar limite primeiro
  v_limit_info := public.check_search_limit(p_user_id);

  IF NOT (v_limit_info->>'can_search')::boolean THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Limite de buscas atingido. Faça upgrade do plano ou compre buscas extras.',
      'limit_info', v_limit_info
    );
  END IF;

  v_subscription_id := (v_limit_info->>'subscription_id')::UUID;
  v_monthly_limit := (v_limit_info->>'monthly_limit')::INTEGER;
  v_searches_used := (v_limit_info->>'searches_used')::INTEGER;

  -- Determinar se é busca extra
  v_is_extra := (v_searches_used >= v_monthly_limit);

  -- Incrementar contador
  UPDATE public.subscriptions
  SET searches_used = searches_used + 1
  WHERE id = v_subscription_id;

  RETURN jsonb_build_object(
    'success', true,
    'is_extra_search', v_is_extra,
    'remaining', (v_limit_info->>'remaining')::INTEGER - 1
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 13. FUNÇÃO: Comprar buscas extras
-- ============================================================
CREATE OR REPLACE FUNCTION public.purchase_extra_searches(
  p_user_id UUID,
  p_quantity INTEGER DEFAULT 5
)
RETURNS JSONB AS $$
DECLARE
  v_subscription_id UUID;
  v_extra_price NUMERIC;
  v_total_cost NUMERIC;
BEGIN
  -- Buscar assinatura e preço de busca extra
  SELECT s.id, p.extra_search_price
  INTO v_subscription_id, v_extra_price
  FROM public.subscriptions s
  JOIN public.plans p ON s.plan_id = p.id
  WHERE s.user_id = p_user_id AND s.status = 'active'
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_subscription_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Nenhuma assinatura ativa encontrada'
    );
  END IF;

  v_total_cost := v_extra_price * p_quantity;

  -- Adicionar buscas extras
  UPDATE public.subscriptions
  SET extra_searches_purchased = extra_searches_purchased + p_quantity
  WHERE id = v_subscription_id;

  -- Registrar no audit log
  INSERT INTO public.audit_logs (user_id, action, details)
  VALUES (
    p_user_id,
    'extra_search_purchased',
    jsonb_build_object(
      'quantity', p_quantity,
      'unit_price', v_extra_price,
      'total_cost', v_total_cost
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'quantity', p_quantity,
    'total_cost', v_total_cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 14. FUNÇÃO: Obter estatísticas do dashboard
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_dashboard_stats(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_limit_info JSONB;
  v_total_searches BIGINT;
  v_total_results BIGINT;
  v_recent_searches JSONB;
  v_source_breakdown JSONB;
BEGIN
  -- Info de limite
  v_limit_info := public.check_search_limit(p_user_id);

  -- Total de buscas do usuário
  SELECT COUNT(*) INTO v_total_searches
  FROM public.searches WHERE user_id = p_user_id;

  -- Total de resultados
  SELECT COUNT(*) INTO v_total_results
  FROM public.results WHERE user_id = p_user_id;

  -- Últimas 5 buscas
  SELECT COALESCE(jsonb_agg(row_to_json(sq)), '[]'::jsonb)
  INTO v_recent_searches
  FROM (
    SELECT id, keywords, date_start, date_end, status, results_count, created_at
    FROM public.searches
    WHERE user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 5
  ) sq;

  -- Breakdown por fonte
  SELECT COALESCE(jsonb_object_agg(source, cnt), '{}'::jsonb)
  INTO v_source_breakdown
  FROM (
    SELECT source, COUNT(*) as cnt
    FROM public.results
    WHERE user_id = p_user_id
    GROUP BY source
  ) sb;

  RETURN jsonb_build_object(
    'subscription', v_limit_info,
    'total_searches', v_total_searches,
    'total_results', v_total_results,
    'recent_searches', v_recent_searches,
    'source_breakdown', v_source_breakdown
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 15. ROW LEVEL SECURITY (RLS)
-- ============================================================

-- Habilitar RLS em todas as tabelas
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- ----- PLANS: leitura pública, escrita apenas admin -----
CREATE POLICY "Planos visíveis para todos os autenticados"
  ON public.plans FOR SELECT
  TO authenticated
  USING (true);

-- ----- USERS: cada usuário vê/edita apenas seu perfil -----
CREATE POLICY "Usuários podem ver seu próprio perfil"
  ON public.users FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Usuários podem atualizar seu próprio perfil"
  ON public.users FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ----- SUBSCRIPTIONS: cada usuário vê apenas suas assinaturas -----
CREATE POLICY "Usuários podem ver suas assinaturas"
  ON public.subscriptions FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Usuários podem atualizar suas assinaturas"
  ON public.subscriptions FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ----- SEARCHES: cada usuário vê/cria apenas suas buscas -----
CREATE POLICY "Usuários podem ver suas buscas"
  ON public.searches FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Usuários podem criar buscas"
  ON public.searches FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuários podem atualizar suas buscas"
  ON public.searches FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ----- RESULTS: cada usuário vê apenas seus resultados -----
CREATE POLICY "Usuários podem ver seus resultados"
  ON public.results FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Usuários podem inserir resultados"
  ON public.results FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuários podem atualizar seus resultados"
  ON public.results FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ----- AUDIT_LOGS: cada usuário vê apenas seus logs -----
CREATE POLICY "Usuários podem ver seus logs"
  ON public.audit_logs FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Usuários podem inserir logs"
  ON public.audit_logs FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- 16. DADOS INICIAIS: Planos
-- ============================================================
INSERT INTO public.plans (name, display_name, description, monthly_searches, price_monthly, extra_search_price, max_keywords_per_search, features) VALUES
(
  'free',
  'Free',
  'Plano gratuito para experimentar o RegulaCHECK',
  3,
  0.00,
  9.90,
  5,
  '["3 buscas por mês", "Até 5 palavras-chave por busca", "Fontes: Anvisa, ABNT, ISO, DOU", "Histórico de 30 dias"]'::jsonb
),
(
  'starter',
  'Starter',
  'Ideal para profissionais que precisam de monitoramento regular',
  20,
  49.90,
  7.90,
  5,
  '["20 buscas por mês", "Até 5 palavras-chave por busca", "Fontes: Anvisa, ABNT, ISO, DOU", "Histórico completo", "Exportação de resultados", "Suporte por e-mail"]'::jsonb
),
(
  'professional',
  'Professional',
  'Para equipes e empresas com alta demanda de compliance',
  100,
  149.90,
  4.90,
  5,
  '["100 buscas por mês", "Até 5 palavras-chave por busca", "Fontes: Anvisa, ABNT, ISO, DOU", "Histórico completo", "Exportação de resultados", "Alertas por e-mail", "API de integração", "Suporte prioritário"]'::jsonb
);

-- ============================================================
-- 17. VIEWS ÚTEIS
-- ============================================================

-- View: resumo da assinatura do usuário
CREATE OR REPLACE VIEW public.user_subscription_summary AS
SELECT
  u.id AS user_id,
  u.email,
  u.full_name,
  p.name AS plan_name,
  p.display_name AS plan_display_name,
  p.monthly_searches,
  p.price_monthly,
  p.extra_search_price,
  s.status AS subscription_status,
  s.searches_used,
  s.extra_searches_purchased,
  (p.monthly_searches + s.extra_searches_purchased - s.searches_used) AS remaining_searches,
  s.current_period_start,
  s.current_period_end
FROM public.users u
LEFT JOIN public.subscriptions s ON u.id = s.user_id AND s.status = 'active'
LEFT JOIN public.plans p ON s.plan_id = p.id;

-- ============================================================
-- 18. GRANT PERMISSIONS
-- ============================================================
-- Garantir que o role anon e authenticated possam acessar as tabelas
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.plans TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
GRANT SELECT, UPDATE ON public.subscriptions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.searches TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.results TO authenticated;
GRANT SELECT, INSERT ON public.audit_logs TO authenticated;
GRANT SELECT ON public.user_subscription_summary TO authenticated;

-- ============================================================
-- FIM DO SCHEMA
-- ============================================================
