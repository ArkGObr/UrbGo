# ArkGO — Roadmap & Análise Comparativa

> Análise realizada em: Abril/2026  
> Comparado com: Uber Flash, iFood Entregador, Rappi, Zippa, Loggi

---

## Resumo Executivo

O ArkGO está bem estruturado para o lançamento MVP. A arquitetura técnica (Flutter + Supabase + FCM) é sólida. As principais lacunas são de **segurança/confiabilidade** (race conditions, GPS background) e de **experiência do entregador** (sem métricas de desempenho, sem histórico de ganhos detalhado).

---

## 🔴 Crítico — Corrigido nesta sessão

| # | Problema | Impacto | Status |
|---|----------|---------|--------|
| C1 | **Race condition em `acceptDelivery`**: dois motoboys podiam aceitar a mesma corrida | Pagamento duplicado, conflito de dados | ✅ Corrigido (`eq('status','pending')` atômico) |
| C2 | **Corridas pendentes sem timeout**: corridas criadas e não aceitas ficavam ativas para sempre | Corridas fantasma, experiência ruim | ✅ Corrigido (pg_cron a cada 5 min, cancela após 30 min) |
| C3 | **GPS parava em segundo plano** (Android): sem Foreground Service, o sistema mata o processo | Motoboy some do mapa do cliente | ✅ Corrigido (Android Foreground Service via `startForegroundService`) |
| C4 | **Sem opção de desistir de uma corrida**: motoboy preso após aceitar, sem conseguir voltar | Corrida bloqueada, motoboy sem saída | ✅ Corrigido (botão "Desistir da Corrida" no `active_run_screen`) |

---

## 🟡 Alta Prioridade — Próximas entregas

| # | Problema | Referência | Esforço |
|---|----------|-----------|---------|
| A1 | **Sem previsão de chegada no app do cliente** | Uber mostra ETA em tempo real | M |
| A2 | **Sem chat cliente ↔ motoboy** | Todos os concorrentes têm | M |
| A3 | **Sem suporte a múltiplos endereços de entrega** | Rappi/Loggi suportam multi-stop | G |
| A4 | **Sem confirmação de entrega por foto** | iFood exige foto na porta | M |
| A5 | **Cancelamento de pedido pelo cliente** sem restrições | Uber limita cancelamento gratuito | P |
| A6 | **Sem paginação no histórico** (client e motoboy) | Pode travar com muitos registros | P |
| A7 | **Não há validação de endereço** ao criar entrega | Usuário pode colocar endereço inválido | M |

---

## 🟢 Média Prioridade — Melhorias de produto

| # | Melhoria | Referência | Esforço |
|---|----------|-----------|---------|
| M1 | **Dashboard de ganhos do motoboy** com gráfico diário/semanal/mensal | Uber/99 têm histórico detalhado | M |
| M2 | **Sistema de nível/reputação do motoboy** visível ao cliente | Uber: ratings + nível | G |
| M3 | **Notificação quando motoboy chegar ao ponto de coleta** | iFood envia alerta ao lojista | P |
| M4 | **Deep links** para abrir entrega diretamente por link externo | Padrão em todos os apps | P |
| M5 | **Onboarding** para novos usuários (tutorial) | Necessário para conversão | M |
| M6 | **Modo offline gracioso** — mensagem clara quando sem internet | Qualidade UX | P |
| M7 | **Suporte a cartão de crédito/débito** no saldo do motoboy | Atualmente só manual? | G |

---

## 🔵 Baixa Prioridade — Polimento e escala

| # | Melhoria | Esforço |
|---|----------|---------|
| B1 | Tela de splash animada com Lottie | P |
| B2 | Tema claro (light mode) | M |
| B3 | Suporte a tablets / landscape | M |
| B4 | Analytics de uso (Mixpanel/Firebase Analytics) | P |
| B5 | Testes automatizados (widget + integration) | G |
| B6 | CI/CD com GitHub Actions | M |
| B7 | Internacionalização (i18n) para expansão | G |

---

## Legenda de esforço

- **P** — Pequeno: < 1 dia
- **M** — Médio: 1–3 dias
- **G** — Grande: > 3 dias

---

## Comparação por funcionalidade

| Funcionalidade | ArkGO | Uber Flash | iFood | Rappi | Zippa |
|----------------|-------|-----------|-------|-------|-------|
| GPS em segundo plano | ✅* | ✅ | ✅ | ✅ | ✅ |
| ETA para cliente | ❌ | ✅ | ✅ | ✅ | ✅ |
| Chat integrado | ❌ | ✅ | ✅ | ✅ | ✅ |
| Confirmação por foto | ❌ | ❌ | ✅ | ✅ | ✅ |
| Multi-stop | ❌ | ✅ | ❌ | ✅ | ✅ |
| Avaliação bidirecional | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dashboard de ganhos | ❌ | ✅ | ✅ | ✅ | ✅ |
| Pagamento in-app | ❌ | ✅ | ✅ | ✅ | ✅ |
| Cancelamento com regras | ❌ | ✅ | ✅ | ✅ | ✅ |
| Timeout de corrida | ✅* | ✅ | ✅ | ✅ | ✅ |

*Corrigido nesta sessão
