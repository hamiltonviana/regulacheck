// ============================================================
// RegulaCHECK - Vercel Serverless Function
// Atualizar assinatura no Supabase após pagamento confirmado
// ============================================================

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://enpxeqlhkdjllukybsme.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

module.exports = async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Método não permitido' });
  }

  try {
    const {
      userId,
      planName,
      asaasSubscriptionId,
      asaasCustomerId
    } = req.body;

    if (!userId || !planName) {
      return res.status(400).json({ error: 'userId e planName são obrigatórios' });
    }

    if (!SUPABASE_SERVICE_KEY) {
      return res.status(500).json({ error: 'Configuração do servidor incompleta' });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Buscar o plan_id
    const { data: plan, error: planError } = await supabase
      .from('plans')
      .select('id, monthly_searches')
      .eq('name', planName)
      .single();

    if (planError || !plan) {
      return res.status(404).json({ error: 'Plano não encontrado' });
    }

    const now = new Date();
    const periodEnd = new Date(now);
    periodEnd.setMonth(periodEnd.getMonth() + 1);

    // Verificar se já existe assinatura ativa
    const { data: existingSub } = await supabase
      .from('subscriptions')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'active')
      .single();

    let result;

    if (existingSub) {
      // Atualizar assinatura existente
      const { data, error } = await supabase
        .from('subscriptions')
        .update({
          plan_id: plan.id,
          status: 'active',
          current_period_start: now.toISOString(),
          current_period_end: periodEnd.toISOString(),
          searches_used: 0,
          extra_searches_purchased: 0,
          asaas_subscription_id: asaasSubscriptionId || null,
          asaas_customer_id: asaasCustomerId || null
        })
        .eq('id', existingSub.id)
        .select()
        .single();

      if (error) throw error;
      result = data;
    } else {
      // Criar nova assinatura
      const { data, error } = await supabase
        .from('subscriptions')
        .insert({
          user_id: userId,
          plan_id: plan.id,
          status: 'active',
          current_period_start: now.toISOString(),
          current_period_end: periodEnd.toISOString(),
          searches_used: 0,
          extra_searches_purchased: 0,
          asaas_subscription_id: asaasSubscriptionId || null,
          asaas_customer_id: asaasCustomerId || null
        })
        .select()
        .single();

      if (error) throw error;
      result = data;
    }

    // Registrar no audit log
    try {
      await supabase
        .from('audit_logs')
        .insert({
          user_id: userId,
          action: 'subscription_upgraded',
          details: {
            plan: planName,
            asaas_subscription_id: asaasSubscriptionId,
            asaas_customer_id: asaasCustomerId
          }
        });
    } catch (e) {
      console.error('Erro ao registrar audit log:', e);
    }

    return res.status(200).json({
      success: true,
      subscription: result
    });

  } catch (error) {
    console.error('Erro na API update-subscription:', error);
    return res.status(500).json({ error: 'Erro interno do servidor', details: error.message });
  }
};
