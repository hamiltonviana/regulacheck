// ============================================================
// RegulaCHECK - Vercel Serverless Function
// Webhook do Asaas para receber notificações de pagamento
// ============================================================

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://enpxeqlhkdjllukybsme.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

module.exports = async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Método não permitido' });
  }

  try {
    const event = req.body;
    console.log('Webhook Asaas recebido:', JSON.stringify(event));

    const eventType = event.event;
    const payment = event.payment;

    if (!payment) {
      return res.status(200).json({ received: true, message: 'Evento sem dados de pagamento' });
    }

    // Eventos de pagamento que nos interessam
    const confirmedEvents = [
      'PAYMENT_CONFIRMED',
      'PAYMENT_RECEIVED'
    ];

    const failedEvents = [
      'PAYMENT_OVERDUE',
      'PAYMENT_DELETED',
      'PAYMENT_REFUNDED',
      'PAYMENT_CHARGEBACK_REQUESTED'
    ];

    if (confirmedEvents.includes(eventType)) {
      // Pagamento confirmado - atualizar assinatura no Supabase
      const userId = payment.externalReference;

      if (userId && SUPABASE_SERVICE_KEY) {
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

        // Buscar o plano baseado no valor
        const planMap = {
          44.90: 'starter',
          152.90: 'professional'
        };

        const planName = planMap[payment.value] || null;

        if (planName) {
          // Buscar o plan_id
          const { data: plan } = await supabase
            .from('plans')
            .select('id')
            .eq('name', planName)
            .single();

          if (plan) {
            // Verificar se já existe assinatura ativa
            const { data: existingSub } = await supabase
              .from('subscriptions')
              .select('id')
              .eq('user_id', userId)
              .eq('status', 'active')
              .single();

            const now = new Date();
            const periodEnd = new Date(now);
            periodEnd.setMonth(periodEnd.getMonth() + 1);

            if (existingSub) {
              // Atualizar assinatura existente
              await supabase
                .from('subscriptions')
                .update({
                  plan_id: plan.id,
                  status: 'active',
                  current_period_start: now.toISOString(),
                  current_period_end: periodEnd.toISOString(),
                  searches_used: 0,
                  extra_searches_purchased: 0,
                  asaas_subscription_id: payment.subscription || null,
                  asaas_customer_id: payment.customer || null
                })
                .eq('id', existingSub.id);
            } else {
              // Criar nova assinatura
              await supabase
                .from('subscriptions')
                .insert({
                  user_id: userId,
                  plan_id: plan.id,
                  status: 'active',
                  current_period_start: now.toISOString(),
                  current_period_end: periodEnd.toISOString(),
                  searches_used: 0,
                  extra_searches_purchased: 0,
                  asaas_subscription_id: payment.subscription || null,
                  asaas_customer_id: payment.customer || null
                });
            }

            // Registrar no audit log
            await supabase
              .from('audit_logs')
              .insert({
                user_id: userId,
                action: 'subscription_upgraded',
                details: {
                  plan: planName,
                  payment_id: payment.id,
                  payment_value: payment.value,
                  billing_type: payment.billingType,
                  asaas_subscription_id: payment.subscription
                }
              });
          }
        }
      }

      return res.status(200).json({ received: true, processed: true });
    }

    if (failedEvents.includes(eventType)) {
      const userId = payment.externalReference;

      if (userId && SUPABASE_SERVICE_KEY) {
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

        // Marcar assinatura como past_due se pagamento falhou
        if (eventType === 'PAYMENT_OVERDUE') {
          await supabase
            .from('subscriptions')
            .update({ status: 'past_due' })
            .eq('user_id', userId)
            .eq('status', 'active');
        }
      }

      return res.status(200).json({ received: true, processed: true });
    }

    // Evento não tratado
    return res.status(200).json({ received: true, processed: false });

  } catch (error) {
    console.error('Erro no webhook Asaas:', error);
    // Retornar 200 mesmo em caso de erro para evitar reenvios
    return res.status(200).json({ received: true, error: error.message });
  }
};
