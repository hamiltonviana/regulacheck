// ============================================================
// RegulaCHECK - Configuração e Utilitários
// ============================================================

const SUPABASE_URL = 'https://enpxeqlhkdjllukybsme.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVucHhlcWxoa2RqbGx1a3lic21lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4NzczMTAsImV4cCI6MjA4OTQ1MzMxMH0.kv6U6Se_VK2pyBNHCBDwoERJOu9EWDMXXYp-AnVCQlw';

// Inicializar Supabase
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ============================================================
// Utilitários
// ============================================================

const Utils = {
  // Formatar data para exibição
  formatDate(dateStr) {
    if (!dateStr) return '—';
    const d = new Date(dateStr);
    return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
  },

  // Formatar data e hora
  formatDateTime(dateStr) {
    if (!dateStr) return '—';
    const d = new Date(dateStr);
    return d.toLocaleDateString('pt-BR', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit'
    });
  },

  // Formatar moeda
  formatCurrency(value) {
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value);
  },

  // Mostrar toast/notificação
  showToast(message, type = 'info') {
    const toast = document.createElement('div');
    const colors = {
      success: 'bg-green-500',
      error: 'bg-red-500',
      info: 'bg-blue-500',
      warning: 'bg-yellow-500 text-gray-900'
    };
    toast.className = `fixed top-4 right-4 z-50 px-6 py-3 rounded-lg text-white shadow-lg transform transition-all duration-300 ${colors[type] || colors.info}`;
    toast.textContent = message;
    document.body.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      setTimeout(() => toast.remove(), 300);
    }, 3000);
  },

  // Mostrar/esconder loading
  showLoading(show = true) {
    let overlay = document.getElementById('loading-overlay');
    if (show) {
      if (!overlay) {
        overlay = document.createElement('div');
        overlay.id = 'loading-overlay';
        overlay.className = 'fixed inset-0 z-50 flex items-center justify-center bg-gray-900/50';
        overlay.innerHTML = `
          <div class="bg-white rounded-2xl p-8 shadow-xl flex flex-col items-center gap-4">
            <div class="w-12 h-12 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin"></div>
            <p class="text-gray-600 font-medium">Carregando...</p>
          </div>`;
        document.body.appendChild(overlay);
      }
      overlay.style.display = 'flex';
    } else if (overlay) {
      overlay.style.display = 'none';
    }
  },

  // Verificar autenticação e redirecionar
  async checkAuth(redirectTo = 'index.html') {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      window.location.href = redirectTo;
      return null;
    }
    return session;
  },

  // Obter sessão atual
  async getSession() {
    const { data: { session } } = await supabase.auth.getSession();
    return session;
  },

  // Logout
  async logout() {
    await supabase.auth.signOut();
    window.location.href = 'index.html';
  },

  // Mapeamento de cores por fonte
  sourceColors: {
    anvisa: { bg: 'bg-red-100', text: 'text-red-700', border: 'border-red-200' },
    abnt: { bg: 'bg-blue-100', text: 'text-blue-700', border: 'border-blue-200' },
    iso: { bg: 'bg-purple-100', text: 'text-purple-700', border: 'border-purple-200' },
    dou: { bg: 'bg-green-100', text: 'text-green-700', border: 'border-green-200' },
    outro: { bg: 'bg-gray-100', text: 'text-gray-700', border: 'border-gray-200' }
  },

  // Badge da fonte
  sourceBadge(source) {
    const s = source.toLowerCase();
    const c = this.sourceColors[s] || this.sourceColors.outro;
    return `<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${c.bg} ${c.text}">${source.toUpperCase()}</span>`;
  },

  // Badge de status
  statusBadge(status) {
    const map = {
      pending: { bg: 'bg-yellow-100', text: 'text-yellow-700', label: 'Pendente' },
      processing: { bg: 'bg-blue-100', text: 'text-blue-700', label: 'Processando' },
      completed: { bg: 'bg-green-100', text: 'text-green-700', label: 'Concluída' },
      failed: { bg: 'bg-red-100', text: 'text-red-700', label: 'Falhou' }
    };
    const s = map[status] || map.pending;
    return `<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${s.bg} ${s.text}">${s.label}</span>`;
  },

  // Mapeamento de ícones por plano
  planIcons: {
    free: '🆓',
    starter: '⚡',
    professional: '🏆'
  }
};
