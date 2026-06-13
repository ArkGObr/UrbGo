# Relatório Completo do App UrbGO / ArkGO

Data de geração: 2026-05-28

## 1. Objetivo do aplicativo

O app é uma plataforma de logística urbana multi-categoria construída em Flutter com backend em Supabase. Ele conecta clientes a entregadores/motoristas para corridas de entrega e transporte, com foco operacional em:

- criação de pedidos pelo cliente
- aceite e execução de corridas pelo entregador
- rastreamento em tempo real
- notificações push
- recarga de carteira do entregador
- pricing dinâmico
- roteamento com OSRM e Google Routes
- analytics operacionais para administração

O projeto usa o nome técnico `ArkGO` no código, enquanto o contexto do produto aparece como `UrbGO` na operação.

## 2. Stack técnica

- App mobile: Flutter
- Estado e DI: Riverpod
- Navegação: GoRouter
- Backend principal: Supabase
- Banco: Postgres via Supabase
- Auth: Supabase Auth
- Realtime: Supabase Realtime
- Push mobile: Firebase Cloud Messaging + `flutter_local_notifications`
- Mapas no app: `flutter_map`
- Roteamento:
  - OSRM para rota base e fallback
  - Google Routes via Edge Function para tráfego ao vivo
  - Gemini em função separada para enriquecimento de rota/analytics
- Pagamentos:
  - PIX via Pagar.me
  - Edge Functions para criação, polling e webhook
- Armazenamento:
  - Supabase Storage

## 3. Perfis de usuário

### 3.1 Cliente

Pode:

- cadastrar conta e autenticar
- criar entrega/corrida
- selecionar categoria de veículo
- informar endereços, destinatário e observações
- acompanhar a corrida em tempo real
- conversar com o entregador por chat
- ver histórico
- avaliar o entregador
- editar perfil e avatar

### 3.2 Motoboy / Entregador

Pode:

- cadastrar conta com documentação
- aguardar liberação operacional
- ficar online/offline
- ver corridas disponíveis
- aceitar corrida
- navegar externamente em app de mapa
- confirmar coleta
- finalizar entrega
- desistir de corrida aceita
- acompanhar carteira e recargas
- ver histórico e dashboard de ganhos
- editar perfil, avatar e documentos

Observação: no código o nome da camada permanece `motoboy`, mas ela já cobre múltiplas categorias de veículo.

### 3.3 Admin

Tem telas dedicadas para:

- dashboard analítico de roteamento
- investor pitch / painel demonstrativo

## 4. Categorias de serviço

As categorias mapeadas em `lib/core/constants/vehicle_categories.dart` são:

- `motoboy`
- `car`
- `bike`
- `mototaxi`
- `van`
- `truck`

Metadados por categoria incluem:

- nome e ícone
- descrição
- capacidade
- capacidade detalhada
- multiplicador de ETA
- flags como `isRide`, `isMotoTaxi`, `isEco`
- limite máximo de distância para bike
- peso máximo

Regras importantes já visíveis no código:

- `bike` tem limite de `3 km`
- `bike` usa navegação em modo bicicleta quando suportado
- `van` e `truck` recebem multiplicadores de preço adicionais
- `round trip` agora é decisão do cliente e adiciona `50%` da tarifa base no retorno

## 5. Estrutura de navegação do app

Rotas principais definidas em `lib/app/router.dart`.

### 5.1 Rotas públicas / autenticação

- `/splash`
- `/login`
- `/register`
- `/check-email`
- `/onboarding`

### 5.2 Rotas do cliente

- `/client/home`
- `/client/create`
- `/client/tracking/:id`
- `/delivery/:id` -> redirect para tracking
- `/client/profile`
- `/client/history`
- `/client/chat/:id`

### 5.3 Rotas do entregador

- `/motoboy/release-pending`
- `/motoboy/home`
- `/motoboy/runs`
- `/motoboy/active/:id`
- `/run/:id` -> redirect para rota ativa
- `/motoboy/wallet`
- `/motoboy/history`
- `/motoboy/profile`
- `/motoboy/chat/:id`
- `/chat/:id` -> redireciona conforme role

### 5.4 Rotas administrativas

- `/admin/analytics`
- `/admin/pitch`

### 5.5 Regras de redirect

O router aplica:

- splash até resolver auth
- onboarding obrigatório na primeira execução
- bloqueio de áreas privadas sem sessão
- redirecionamento para home adequada por role
- bloqueio de motoboy não liberado para a tela `release-pending`

## 6. Inicialização do app

Arquivo principal: `lib/main.dart`

Fluxo de bootstrap:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. carga do `.env`
3. inicialização do Firebase
4. registro do `FirebaseMessaging.onBackgroundMessage`
5. inicialização do Supabase
6. configuração de deep links com `app_links`
7. execução do app com `ProviderScope`

Deep links são usados para:

- confirmação de e-mail / recuperação de sessão via `getSessionFromUrl`

## 7. Módulos funcionais

## 7.1 Autenticação e onboarding

Arquivos centrais:

- `lib/features/auth/data/auth_repository.dart`
- `lib/features/auth/domain/auth_provider.dart`
- `lib/features/auth/domain/user_model.dart`
- telas em `lib/features/auth/presentation/`

Funcionalidades:

- cadastro de cliente e entregador
- login com e-mail e senha
- reset de senha
- sessão persistida pelo Supabase
- onboarding de primeira execução
- tela de checagem de e-mail
- tela de espera para liberação de entregador

Detalhes relevantes:

- `signUp` envia `emailRedirectTo: 'arkgo://login-callback'`
- entregador pode subir documentos já no cadastro
- após login/cadastro, o app inicializa notificações e persiste o FCM token

## 7.2 Cadastro operacional do entregador

No cadastro de entregador são tratados:

- CPF
- RG
- placa
- categoria do veículo
- modelo e ano
- CNH
- categoria da CNH
- validade da CNH
- CEP, número, complemento, rótulo do endereço
- upload de:
  - RG
  - selfie com documento
  - CNH
  - documento do veículo
  - autorização adicional

Bucket de storage:

- `driver-documents`

Status operacionais de aprovação:

- `pendingDocuments`
- `pendingReview`
- `approved`
- `rejected`

## 7.3 Fluxo do cliente

### Home do cliente

A partir das rotas e providers, a home do cliente organiza:

- entregas ativas
- acesso à criação de nova entrega
- acesso ao histórico
- acesso ao perfil

### Criação de entrega

Tela: `lib/features/client/presentation/create_delivery_screen.dart`

Fluxo funcional:

1. escolha do veículo
2. endereços
3. detalhes
4. confirmação

Campos usados no fluxo:

- coleta
- entrega
- parada extra opcional
- destinatário
- telefone do destinatário
- observações
- item frágil
- valor declarado
- ajudantes
- ida e volta
- agendamento
- tipo de carga
- método de pagamento

Comportamentos relevantes:

- autocomplete e geocoding nativo
- cálculo de rota
- múltiplas rotas alternativas quando possível
- cálculo de preço base
- cálculo com tráfego ao vivo
- validação de distância para bike
- cobrança de retorno de `50%` da tarifa base quando `ida e volta` estiver ativa

### Tracking do cliente

Tela: `tracking_screen.dart`

Funcionalidades esperadas pelo código:

- acompanhar status da entrega
- ver posição do entregador em tempo real
- visualizar rota
- chat com entregador
- recursos adicionais de rastreamento/compartilhamento
- avaliação após conclusão

### Histórico do cliente

Tela: `client_history_screen.dart`

Consulta entregas:

- concluídas
- canceladas

### Perfil do cliente

Tela: `client_profile_screen.dart`

Permite:

- atualizar dados básicos
- upload de avatar

Bucket:

- `avatars`

### Chat cliente

Tela: `chat_screen.dart`

Recurso:

- troca de mensagens por entrega usando `delivery_messages`

## 7.4 Fluxo do entregador

### Home do entregador

Tela: `motoboy_home_screen.dart`

Funções centrais inferidas do código:

- exibir dados da conta e saldo
- alternar online/offline
- monitorar corrida ativa
- abrir corridas disponíveis
- abrir carteira
- abrir histórico
- abrir perfil

### Corridas disponíveis

Tela: `available_runs_screen.dart`

Comportamentos:

- carrega corridas com base na posição atual
- filtra por raio no cliente
- respeita categoria e fila de notificação
- permite aceitar corrida
- valida saldo antes do aceite

### Corrida ativa

Tela: `active_run_screen.dart`

Recursos implementados:

- leitura da entrega atual
- rastreamento GPS em foreground
- rota no mapa
- monitoramento do GPS do aparelho
- notificação persistente de corrida em andamento
- ação direta por notificação:
  - confirmar coleta
  - finalizar entrega
- confirmação de coleta
- finalização de entrega com foto opcional
- desistência da corrida
- chat com cliente
- copiloto de rota / reroute
- botão para abrir navegação externa

Navegação externa:

- Google Maps
- Waze
- Apple Maps no iOS
- fallback via navegador

### Wallet / recarga

Tela: `wallet_screen.dart`

Bottom sheet: `recharge_bottom_sheet.dart`

Funcionalidades:

- exibir saldo
- listar transações
- gerar cobrança PIX
- modo simulado em debug
- polling de confirmação
- timeout do QR Code

### Histórico do entregador

Tela: `run_history_screen.dart`

Traz corridas:

- concluídas
- canceladas

### Perfil do entregador

Tela: `motoboy_profile_screen.dart`

Permite:

- editar avatar
- editar descrição
- reenviar/gerenciar documentos
- atualizar dados cadastrais do motorista

## 7.5 Chat

Arquivo: `lib/features/client/data/chat_repository.dart`

Tabela:

- `delivery_messages`

Capacidades:

- carregar até 100 mensagens por entrega
- enviar mensagem
- acompanhar mensagens em realtime por canal dedicado

## 7.6 Avaliação

Arquivo: `lib/features/client/data/rating_repository.dart`

Tabela:

- `delivery_ratings`

Capacidades:

- enviar nota
- enviar comentário opcional
- checar se já avaliou
- carregar mapa de avaliações do cliente

Trigger SQL associado:

- atualiza `avg_rating` e `total_ratings` do entregador

## 7.7 Roteamento

### Roteamento base

Arquivo: `lib/core/services/route_service.dart`

Funções:

- `getRouteWithInfo`
- `getRoute`
- `getRouteWithStops`
- `getRouteChoices`

Fonte principal:

- OSRM público

Fallback:

- estimativa local via Haversine x `1.4`

### Roteamento híbrido

Arquivo: `lib/data/repositories/route_repository.dart`

Lógica:

- decide se consulta tráfego ao vivo
- se necessário, combina:
  - OSRM
  - Edge Function `routing-decision`

Critérios para tráfego ao vivo:

- corrida urgente
- distância maior que `8 km`
- horário de pico em dia útil

### Roteamento inteligente / analytics

Há ainda funções server-side para:

- `routing-decision`
- `gemini-routing`
- `analytics-metrics`
- `generate-report`
- `weekly-report-cron`

## 7.8 Pricing

Arquivos:

- `lib/core/constants/vehicle_categories.dart`
- `lib/data/services/fare_calculator.dart`
- `lib/core/services/dynamic_pricing_service.dart`

Elementos do preço:

- tarifa base por faixa de km
- multiplicador por categoria
- adicional de tráfego
- pedágio estimado
- taxa de ajudante
- taxa de retorno `50%` da base em `ida e volta`
- multiplicadores dinâmicos de pricing rules

Tabela remota de pricing:

- `pricing_rules`

Breakdown exibido ao cliente:

- tarifa base
- adicional de tráfego
- retorno 50% quando aplicável
- pedágio
- total

## 7.9 Notificações

Arquivo central:

- `lib/core/services/notification_service.dart`

Funcionalidades:

- pedir permissão
- criar canais Android
- salvar FCM token no banco
- remover token no logout
- exibir notificação local quando app está em foreground
- lidar com toque em notificação
- iniciar foreground service na corrida ativa

Canais Android:

- `arkgo_channel`
- `arkgo_reengagement`
- `ongoing_run_channel`

Tipos de push tratados no ecossistema:

- nova corrida
- mudança de status da entrega
- recarga confirmada
- lembretes de reengajamento
- notificação de corrida em andamento

## 7.10 Realtime

Uso de realtime do Supabase:

- stream da entrega específica
- stream do motoboy
- stream da corrida ativa
- stream das mensagens do chat
- watch da localização do entregador
- watch de corridas disponíveis

## 7.11 Analytics / Admin

### Dashboard analítico

Provider: `analyticsProvider`

Consome:

- Edge Function `analytics-metrics`

Indicadores retornados:

- total de corridas analisadas
- minutos economizados
- ratio médio de tráfego
- total de pedágios
- precisão da IA
- taxa de aceitação de reroute
- série temporal
- corredores principais
- análise de custo
- eventos recentes
- número de corridas com IA ativas

### Investor pitch

Tela adicional focada em apresentação do produto/analytics.

## 8. Consultas e operações no banco por módulo

Esta seção resume as operações encontradas diretamente no código Flutter e nas Edge Functions.

## 8.1 Tabela `users`

Leituras:

- buscar usuário da sessão
- buscar token FCM

Escritas:

- update de `fcm_token`
- limpeza de `fcm_token`
- update de nome, telefone, avatar, descrição
- upsert de usuário em fallback de cadastro

Campos relevantes observados:

- `id`
- `name`
- `phone`
- `email`
- `role`
- `status`
- `is_released`
- `block_reason`
- `avatar_url`
- `description`
- `fcm_token`

## 8.2 Tabela `motoboys`

Leituras:

- buscar perfil do entregador
- stream em tempo real
- validar saldo
- buscar dados para recarga PIX

Escritas:

- upsert de registro operacional
- toggle online/offline
- update de posição GPS
- update de saldo por recarga
- update de rating agregada
- update de documentos e dados cadastrais

Campos observados:

- saldo
- online
- geolocalização
- veículo
- documentos
- aprovação
- reputação

## 8.3 Tabela `deliveries`

Leituras:

- listar entregas do cliente
- listar histórico do cliente
- buscar entrega específica
- stream de entrega
- listar corridas pendentes
- listar histórico do entregador
- buscar corrida ativa

Escritas:

- criar entrega
- cancelar entrega
- aceitar entrega
- desistir corrida
- confirmar coleta
- finalizar entrega
- salvar foto da entrega

Campos funcionais encontrados:

- cliente
- entregador
- origem/destino
- valor
- comissão
- método de pagamento
- categoria de veículo
- status
- distância
- parada extra
- foto de entrega
- destinatário
- observações
- item frágil
- valor declarado
- ajudantes
- ida e volta
- agendamento
- tipo de carga

## 8.4 Tabela `delivery_messages`

Leituras:

- mensagens por `delivery_id`

Escritas:

- inserção de nova mensagem

Realtime:

- insert watch por entrega

## 8.5 Tabela `delivery_ratings`

Leituras:

- verificar se já avaliou
- obter notas por cliente

Escritas:

- inserir avaliação

## 8.6 Tabela `pricing_rules`

Leituras:

- buscar regras ativas de pricing dinâmico

## 8.7 Tabela `route_sessions`

Escritas:

- salvar sessão de rota ao criar/acompanhar corrida

Leituras:

- analytics-metrics usa a tabela como fonte principal

## 8.8 Tabela `route_cache`

Uso server-side:

- cache de respostas de roteamento
- atualização de `hit_count`
- limpeza de cache antigo

## 8.9 Tabela `delivery_notification_targets`

Uso:

- fila de destinatários de notificação por corrida
- base para cascata e elegibilidade de corridas disponíveis

## 8.10 Tabela `recharges`

Uso:

- armazenar recargas PIX
- verificar status no polling
- webhook de confirmação

## 8.11 Tabela `transactions`

Uso:

- registrar recarga
- compor extrato da carteira

## 9. Buckets de storage

Buckets identificados no código:

- `avatars`
- `driver-documents`
- `delivery-photos`
- `reports`

Uso por bucket:

- `avatars`: avatar de cliente e entregador
- `driver-documents`: documentos do entregador
- `delivery-photos`: foto de confirmação de entrega
- `reports`: PDFs gerados pelo analytics

## 10. Edge Functions

## 10.1 `routing-decision`

Objetivo:

- decidir entre OSRM e Google Routes
- retornar rota com ou sem tráfego ao vivo

Entrada:

- `origin`
- `destination`
- `isUrgent`

Saída:

- distância
- duração
- duração com tráfego
- `trafficRatio`
- polyline
- source

## 10.2 `gemini-routing`

Objetivo:

- calcular rota com Google Routes
- enriquecer com Gemini
- armazenar em cache

Saída:

- rota otimizada
- ETA
- alerts
- `trafficRatio`
- custo de pedágio

## 10.3 `analytics-metrics`

Objetivo:

- agregar `route_sessions`
- servir dashboard administrativo

Proteção:

- token administrativo ou service role

## 10.4 `generate-report`

Objetivo:

- montar PDF executivo com base no analytics
- salvar em storage
- gerar signed URL

## 10.5 `weekly-report-cron`

Objetivo:

- disparar a geração periódica do relatório PDF

## 10.6 `create-pix-charge`

Objetivo:

- criar cobrança PIX na Pagar.me
- buscar dados do entregador
- persistir recarga
- retornar QR Code e expiração

## 10.7 `check-pix-status`

Objetivo:

- consultar status da recarga
- creditar saldo atomicamente
- registrar transação

## 10.8 `pix-webhook`

Objetivo:

- receber confirmação server-to-server da Pagar.me
- validar assinatura
- creditar saldo atomicamente
- registrar transação
- enviar push de confirmação

## 10.9 `simulate-recharge`

Objetivo:

- simular recarga em desenvolvimento

## 10.10 `send-push`

Objetivo:

- envio de push via FCM HTTP v1
- suporta token único ou múltiplos tokens

## 11. Triggers, funções SQL e cron jobs

O repositório contém muitas versões históricas de SQL. O comportamento final mais importante observado é:

### Auth / provisionamento

- trigger em `auth.users` para criar/sincronizar `users` e `motoboys`

### Push de novas corridas

- função `notify_motoboys_new_delivery`
- trigger em `deliveries`

### Mudança de status da entrega

- trigger para notificar cliente e/ou entregador quando status muda

### Recarga confirmada

- trigger / fluxo SQL para notificar recarga

### Rating do entregador

- trigger em `delivery_ratings` para recalcular média e total

### Fila em cascata

- `delivery_notification_targets`
- `process_delivery_notification_queue`
- cron recorrente para liberar notificações em ondas

### Aviso de chegada à coleta

- trigger em `motoboys.current_lat/current_lng`
- quando distância até coleta é pequena, notifica cliente

### Timeout de corridas pendentes

- função `cancel_stale_pending_deliveries`
- cron para cancelar pedidos pendentes antigos

### Reengajamento de entregadores inativos

- função `notify_inactive_motoboys`
- cron de lembrete

### Carteira / crédito atômico

- função RPC `credit_wallet_if_pending`
- evita crédito duplicado por polling e webhook

## 12. Fluxo de negócio da entrega

Fluxo padrão consolidado:

1. cliente autenticado cria a entrega
2. entrega entra como `pending`
3. trigger monta fila de notificação para entregadores elegíveis
4. entregador recebe push
5. entregador aceita corrida
6. entrega vai para `accepted`
7. cliente pode acompanhar localização
8. entregador confirma coleta
9. entrega vai para `in_progress`
10. entregador navega externamente no app de mapa preferido
11. entregador finaliza entrega
12. entrega vai para `completed`
13. cliente pode avaliar

Desvios previstos:

- cancelamento pelo cliente
- desistência do entregador
- timeout de corrida pendente

## 13. Regras de fallback de categoria

Migration recente: `20260528_delivery_category_fallbacks.sql`

Regras:

- entrega `bike` sem `bike` online elegível pode ser oferecida a `motoboy`
- entrega `motoboy` com até `3 km`, sem `motoboy` online elegível, pode ser oferecida a `bike`

Além disso:

- a listagem de corridas do entregador tenta respeitar a fila `delivery_notification_targets`

## 14. Providers e estado

Principais providers identificados:

- `authNotifierProvider`
- `clientDeliveriesProvider`
- `activeClientDeliveriesProvider`
- `deliveryStreamProvider`
- `clientHistoryProvider`
- `clientRatingsProvider`
- `motoboyStreamProvider`
- `availableRunsProvider`
- `activeRunProvider`
- `transactionsProvider`
- `runHistoryProvider`
- `earningsDashboardProvider`
- `analyticsProvider`
- `notificationServiceProvider`
- `routeRepositoryProvider`
- `routeServiceProvider`
- `connectivityProvider`
- `onboardingSeenProvider`

## 15. Integrações externas

### Supabase

- Auth
- Database
- Realtime
- Storage
- Edge Functions

### Firebase

- FCM foreground
- FCM background
- token push

### Pagar.me

- criação de PIX
- consulta de charge
- webhook

### Google

- Google Routes API
- infraestrutura de geocoder nativo Android, quando disponível via sistema

### OSRM

- rota base e alternativas

### Gemini

- interpretação/enriquecimento de rota em função dedicada

## 16. Inventário de telas

Telas encontradas:

- `SplashScreen`
- `LoginScreen`
- `RegisterScreen`
- `CheckEmailScreen`
- `OnboardingScreen`
- `MotoboyReleasePendingScreen`
- `ClientHomeScreen`
- `CreateDeliveryScreen`
- `TrackingScreen`
- `ClientProfileScreen`
- `ClientHistoryScreen`
- `ChatScreen`
- `MotoboyHomeScreen`
- `AvailableRunsScreen`
- `ActiveRunScreen`
- `WalletScreen`
- `MotoboyProfileScreen`
- `RunHistoryScreen`
- `NavigationScreen`
- `AnalyticsDashboardScreen`
- `InvestorPitchScreen`

Observação:

- `NavigationScreen` existe no código, mas o fluxo atual do entregador já está direcionado para navegação externa, não navegação embutida como modo principal.

## 17. Segurança e controles operacionais observados

- bloqueio de acesso do motoboy não liberado
- limpeza de token FCM no logout
- foreground service para corrida ativa
- aceite atômico por `status = pending`
- crédito de carteira atômico por RPC
- webhook com validação de assinatura HMAC da Pagar.me
- cache com ETag no analytics
- signed URL para relatórios PDF

## 18. Limitações e pontos de atenção encontrados no código

Com base no estado atual do repositório:

- há muitas migrations/SQL históricos, com sobreposição de versões de funções
- o `README.md` ainda está genérico e não documenta o produto
- parte da documentação antiga ainda cita gaps já corrigidos no código
- existem consultas que dependem de RLS e de alinhamento fino entre app e banco
- `flutter test` não pôde ser validado neste ambiente sem binário Flutter
- a cobertura de testes é pequena frente à complexidade operacional

## 19. Resumo executivo final

O app já implementa um ecossistema relativamente completo de operação logística:

- autenticação
- onboarding
- cadastro documental de entregador
- criação de pedidos multi-categoria
- pricing dinâmico
- roteamento com fallback
- tracking em tempo real
- chat
- avaliação
- carteira com recarga PIX
- notificações push
- triggers operacionais em banco
- analytics e geração de relatórios

O núcleo do produto está estruturado em três eixos:

- operação de entrega/corrida
- operação financeira do entregador
- observabilidade operacional via analytics

## 20. Arquivos-base usados para este relatório

Principais fontes inspecionadas:

- `lib/main.dart`
- `lib/app/router.dart`
- `lib/features/auth/**`
- `lib/features/client/**`
- `lib/features/motoboy/**`
- `lib/core/services/**`
- `lib/data/**`
- `supabase/functions/**`
- `supabase/migrations/**`
- `supabase/sql/**`
- `docs/COMPETITIVE_ANALYSIS.md`
- `docs/MIGRATION.sql`
- `ROADMAP.md`

