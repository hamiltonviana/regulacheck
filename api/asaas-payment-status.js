// ============================================================
// RegulaCHECK - Vercel Serverless Function
// Verificar status de pagamento no Asaas
// ============================================================

const ASAAS_API_URL = 'https://api.asaas.com/v3';
const ASAAS_API_KEY = process.env.ASAAS_API_KEY;

module.exports = async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Método não permitido' });
  }

  try {
    const { paymentId } = req.query;

    if (!paymentId) {
      return res.status(400).json({ error: 'paymentId é obrigatório' });
    }

    // Buscar status do pagamento
    const response = await fetch(`${ASAAS_API_URL}/payments/${paymentId}`, {
      method: 'GET',
      headers: {
        'accept': 'application/json',
        'access_token': ASAAS_API_KEY
      }
    });

    const data = await response.json();

    if (!response.ok) {
      return res.status(response.status).json({
        error: 'Erro ao buscar pagamento',
        details: data
      });
    }

    // Buscar informações adicionais se for PIX
    let pixInfo = null;
    if (data.billingType === 'PIX' && data.status === 'PENDING') {
      try {
        const pixResponse = await fetch(
          `${ASAAS_API_URL}/payments/${paymentId}/pixQrCode`,
          {
            method: 'GET',
            headers: {
              'accept': 'application/json',
              'access_token': ASAAS_API_KEY
            }
          }
        );
        if (pixResponse.ok) {
          pixInfo = await pixResponse.json();
        }
      } catch (e) {
        // PIX info pode não estar disponível
      }
    }

    return res.status(200).json({
      success: true,
      payment: {
        id: data.id,
        status: data.status,
        value: data.value,
        billingType: data.billingType,
        dueDate: data.dueDate,
        invoiceUrl: data.invoiceUrl,
        bankSlipUrl: data.bankSlipUrl,
        confirmedDate: data.confirmedDate,
        paymentDate: data.paymentDate
      },
      pix: pixInfo
    });

  } catch (error) {
    console.error('Erro na API asaas-payment-status:', error);
    return res.status(500).json({ error: 'Erro interno do servidor' });
  }
};
