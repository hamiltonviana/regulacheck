// ============================================================
// RegulaCHECK - Vercel Serverless Function
// Criar ou buscar cliente no Asaas
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
    const { name, cpfCnpj, email, phone, externalReference } = req.body;

    if (!name || !cpfCnpj) {
      return res.status(400).json({ error: 'Nome e CPF/CNPJ são obrigatórios' });
    }

    // Primeiro, tentar buscar cliente existente pelo CPF/CNPJ
    const searchResponse = await fetch(
      `${ASAAS_API_URL}/customers?cpfCnpj=${cpfCnpj.replace(/\D/g, '')}`,
      {
        method: 'GET',
        headers: {
          'accept': 'application/json',
          'access_token': ASAAS_API_KEY
        }
      }
    );

    const searchData = await searchResponse.json();

    if (searchData.data && searchData.data.length > 0) {
      // Cliente já existe, retornar o primeiro encontrado
      return res.status(200).json({
        success: true,
        customer: searchData.data[0],
        isNew: false
      });
    }

    // Criar novo cliente
    const createResponse = await fetch(`${ASAAS_API_URL}/customers`, {
      method: 'POST',
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
        'access_token': ASAAS_API_KEY
      },
      body: JSON.stringify({
        name,
        cpfCnpj: cpfCnpj.replace(/\D/g, ''),
        email: email || undefined,
        phone: phone || undefined,
        externalReference: externalReference || undefined,
        notificationDisabled: false
      })
    });

    const createData = await createResponse.json();

    if (!createResponse.ok) {
      return res.status(createResponse.status).json({
        error: 'Erro ao criar cliente no Asaas',
        details: createData
      });
    }

    return res.status(201).json({
      success: true,
      customer: createData,
      isNew: true
    });

  } catch (error) {
    console.error('Erro na API asaas-customer:', error);
    return res.status(500).json({ error: 'Erro interno do servidor' });
  }
};
