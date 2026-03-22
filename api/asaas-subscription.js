// ============================================================
// RegulaCHECK - Vercel Serverless Function
// Criar assinatura recorrente no Asaas
// ============================================================

const ASAAS_API_URL = 'https://api.asaas.com/v3';
const ASAAS_API_KEY = process.env.ASAAS_API_KEY;

module.exports = async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,POST');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Método não permitido' });
  }

  try {
    const {
      customerId,
      billingType,
      value,
      planName,
      userId,
      // Dados de cartão de crédito (opcional)
      creditCard,
      creditCardHolderInfo
    } = req.body;

    if (!customerId || !value || !planName) {
      return res.status(400).json({
        error: 'customerId, value e planName são obrigatórios'
      });
    }

    // Data de vencimento: próximo dia útil (amanhã)
    const nextDueDate = new Date();
    nextDueDate.setDate(nextDueDate.getDate() + 1);
    const dueDateStr = nextDueDate.toISOString().split('T')[0];

    // Montar payload da assinatura
    const subscriptionPayload = {
      customer: customerId,
      billingType: billingType || 'UNDEFINED',
      value: parseFloat(value),
      nextDueDate: dueDateStr,
      cycle: 'MONTHLY',
      description: `RegulaCHECK - Plano ${planName}`,
      externalReference: userId || undefined
    };

    // Se for cartão de crédito, adicionar dados do cartão
    if (billingType === 'CREDIT_CARD' && creditCard && creditCardHolderInfo) {
      subscriptionPayload.creditCard = creditCard;
      subscriptionPayload.creditCardHolderInfo = creditCardHolderInfo;
    }

    // Criar assinatura no Asaas
    const endpoint = (billingType === 'CREDIT_CARD' && creditCard)
      ? `${ASAAS_API_URL}/subscriptions`
      : `${ASAAS_API_URL}/subscriptions`;

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
        'access_token': ASAAS_API_KEY
      },
      body: JSON.stringify(subscriptionPayload)
    });

    const data = await response.json();

    if (!response.ok) {
      return res.status(response.status).json({
        error: 'Erro ao criar assinatura no Asaas',
        details: data
      });
    }

    // Buscar a primeira cobrança gerada para obter o link de pagamento
    let paymentInfo = null;
    try {
      const paymentsResponse = await fetch(
        `${ASAAS_API_URL}/subscriptions/${data.id}/payments`,
        {
          method: 'GET',
          headers: {
            'accept': 'application/json',
            'access_token': ASAAS_API_KEY
          }
        }
      );
      const paymentsData = await paymentsResponse.json();

      if (paymentsData.data && paymentsData.data.length > 0) {
        const firstPayment = paymentsData.data[0];
        paymentInfo = {
          paymentId: firstPayment.id,
          invoiceUrl: firstPayment.invoiceUrl,
          bankSlipUrl: firstPayment.bankSlipUrl,
          status: firstPayment.status,
          value: firstPayment.value,
          dueDate: firstPayment.dueDate
        };

        // Se for PIX, buscar QR Code
        if (billingType === 'PIX' || billingType === 'UNDEFINED') {
          try {
            const pixResponse = await fetch(
              `${ASAAS_API_URL}/payments/${firstPayment.id}/pixQrCode`,
              {
                method: 'GET',
                headers: {
                  'accept': 'application/json',
                  'access_token': ASAAS_API_KEY
                }
              }
            );
            if (pixResponse.ok) {
              const pixData = await pixResponse.json();
              paymentInfo.pixQrCode = pixData;
            }
          } catch (e) {
            // PIX QR Code pode não estar disponível ainda
          }
        }
      }
    } catch (e) {
      console.error('Erro ao buscar pagamentos da assinatura:', e);
    }

    return res.status(201).json({
      success: true,
      subscription: data,
      payment: paymentInfo
    });

  } catch (error) {
    console.error('Erro na API asaas-subscription:', error);
    return res.status(500).json({ error: 'Erro interno do servidor' });
  }
};
