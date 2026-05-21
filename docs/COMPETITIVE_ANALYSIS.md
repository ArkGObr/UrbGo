# ArkGO — Análise Competitiva por Categoria

> Data: Abril 2026 | Revisão baseada em pesquisa de mercado das maiores plataformas do Brasil e global.

---

## VISÃO GERAL DO APLICATIVO

O ArkGO é uma plataforma de logística urbana multi-categoria que conecta clientes a entregadores/motoristas. Suporta 6 categorias de veículo: Moto, Carro, Bike, MotoTáxi, Utilitário (Van) e Carreto (Caminhão).

---

## CATEGORIAS E BENCHMARKS

### Categoria 1 — Moto Entregas

**Benchmarks:** Uber Courier, Lalamove LalaGo/LalaPro, Loggi, inDrive Courier

| Feature | Uber Courier | Lalamove | Loggi | **ArkGO** |
|---|---|---|---|---|
| Nome + telefone do destinatário | ✅ obrigatório | ✅ por parada | ✅ | ❌ → **implementar** |
| Nome + telefone do remetente | ✅ | ✅ | ✅ | ❌ → **implementar** |
| Observações para o entregador | ✅ | ✅ 1.500 chars | ✅ | ❌ → **implementar** |
| Valor declarado / seguro | ✅ 1,5% | ❌ | ✅ = NF | ❌ → **implementar** |
| PIN de confirmação | ✅ opt-in | ❌ | ❌ | ❌ |
| Prova de entrega (foto) | ✅ | ✅ foto+ass. | ❌ | ✅ (driver side) |
| Multi-parada | ❌ | ✅ até 20 | ❌ | ✅ 1 extra |
| Agendamento futuro | ❌ | ✅ | ✅ | ❌ → **implementar (van/truck)** |
| Flag fragilidade | ❌ | ✅ API | ❌ | ❌ → **implementar** |
| Dimensões / peso do pacote | ❌ | ✅ enum | ✅ obrig. | ❌ |

**Gaps críticos:** Nome+telefone destinatário, observações, valor declarado, flag frágil.

**Pricing:** Tabela por km (R$8–R$50 para até 25km), +R$2/km após. Surge dinâmico. ✅ Implementado.

**Lei brasileira (motoboy):** CNH Cat. A com EAR, mínimo 21 anos, curso Detran, colete, baú, antena corta-pipa. Plataforma já valida CNH+EAR nos documentos do motorista.

---

### Categoria 2 — Carro (Entrega)

**Benchmarks:** Uber Courier Car, Lalamove Hatch/Sedan/Utilitário, inDrive Delivery

| Feature | Uber Courier | Lalamove | **ArkGO** |
|---|---|---|---|
| Capacidade em kg + litros na UI | ❌ implicit | ✅ "300kg / 375L" | ❌ → **melhorar** |
| Sugestão upgrade/downgrade | ✅ | ✅ | ❌ → **implementar** |
| Ajudante (helper) | ❌ | ✅ médio+ | ❌ |
| Viagem de volta (round trip) | ❌ | ✅ | ❌ → **implementar** |
| Mesmos gaps do moto | ✅ | ✅ | ❌ |

**Decisão de posicionamento:** Carro = entrega de carga maior (porta-malas), não transporte de passageiro. Mototáxi cobre o caso de passageiro.

---

### Categoria 3 — Bike Entregas

**Benchmarks:** iFood Pedal, Rappi Cycling, inDrive on-foot/bike

| Feature | iFood | Rappi | **ArkGO** |
|---|---|---|---|
| Limite de raio (≤ 3km) validado | ✅ backend | ✅ backend | ❌ → **implementar** |
| Limite de peso aplicado (≤ 5kg) | ✅ implicit | ✅ | ❌ só texto |
| Seguro acidente do entregador | ✅ gratuito | ✅ | ❌ |
| Badge sustentabilidade | ✅ marketing | ✅ | ❌ → **implementar** |

**Requisitos do entregador bike:** RG, CPF, foto, conta bancária, mochila/caixa térmica. SEM CNH. Barreira de entrada muito menor que moto.

**Gap crítico:** Sem validação de distância/peso → pedidos impossíveis (ex: 15km, 10kg para bike).

---

### Categoria 4 — Moto Táxi (Corrida de Passageiro)

**Benchmarks:** 99Moto, Uber Moto, inDrive Moto

| Feature | 99Moto | Uber Moto | inDrive | **ArkGO** |
|---|---|---|---|---|
| Fluxo sem campos de pacote | ✅ | ✅ | ✅ | ❌ usa fluxo de entrega |
| Aviso de capacete obrigatório | ✅ 1ª viagem | ✅ | ✅ | ❌ → **implementar** |
| Seguro pessoal (até R$100k) | ✅ | ✅ | ❌ | ❌ → **informar** |
| Botão SOS durante corrida | ✅ | ✅ | ✅ | ❌ → **implementar** |
| Compartilhar rota com contato | ✅ | ✅ | ✅ | ❌ → **implementar** |
| Gravação de áudio | ✅ 99Moto | ❌ | ❌ | ❌ |
| Aviso legal por cidade | ✅ SP ban | ✅ | ✅ | ❌ |

**Gap crítico — Conceitual:** MotoTáxi é uma corrida, não uma entrega. O fluxo atual é completamente errado para este caso de uso. Precisa de tela separada com origem/destino (não coleta/entrega), sem campos de pacote, com segurança explícita.

**Status legal:** São Paulo baniu mototaxi por apps (2025). Disponível em 3.300+ cidades do Brasil. Precisaria de validação por cidade em versão futura.

---

### Categoria 5 — Utilitário (Van/Furgão)

**Benchmarks:** Lalamove Utilitário/Van, AiQFrete, frete.com urban

| Feature | Lalamove | AiQFrete | **ArkGO** |
|---|---|---|---|
| Capacidade detalhada (kg + litros + cm) | ✅ "1.000kg / 267×179×166cm" | ✅ | ❌ só "650kg" → **melhorar** |
| Ajudante (helper) — 1 ou 2 | ✅ obrigatório | ✅ | ❌ → **implementar** |
| Custo extra discriminado por helper | ✅ | ✅ | ❌ |
| Opção "ida e volta" | ✅ | ❌ | ❌ → **implementar** |
| Tipo de carga (Móveis/Eletro/Material) | ✅ prompt | ❌ | ❌ → **implementar** |
| Agendamento | ✅ | ✅ | ❌ → **implementar** |

**Gap crítico:** Ausência do ajudante. Para mudança de móveis/eletrodomésticos, o motorista não consegue trabalhar sozinho. Gera cancelamentos e insatisfação.

---

### Categoria 6 — Carreto (antes "Caminhão")

**Benchmarks:** FreteBras/Frete.com, TruckPad, Lalamove Carreto, CargoX

**Decisão estratégica (implementada):** Reposicionado de "Caminhão" (frete rodoviário) para "Carreto" (mudanças urbanas), seguindo o modelo da Lalamove. Frete rodoviário requer RNTRC (ANTT), CIOT, Piso Mínimo ANTT — altamente regulamentado.

| Feature | Lalamove Carreto | FreteBras | **ArkGO** |
|---|---|---|---|
| Tipo de carga (Móveis/Obra/Comercial) | ✅ | ✅ (espécie) | ❌ → **implementar** |
| Ajudante (1/2/3) | ✅ | N/A | ❌ → **implementar** |
| Agendamento obrigatório | ✅ | ✅ | ❌ → **implementar** |
| Número de cômodos | ❌ | ❌ | ❌ → **implementar** |
| Preço discriminado (frete + helpers) | ✅ | ✅ | ❌ |

**Diferença de modelo:** FreteBras usa marketplace de frete (shipper posta, motoristas ofertam). Para ArkGO: modelo on-demand (cliente pede, motorista aceita) é adequado para carreto urbano/mudanças.

---

## GAPS CRÍTICOS (C) — IMPACTAM HOJE

| # | Gap | Categorias afetadas | Status |
|---|---|---|---|
| **C1** | Nome + telefone do destinatário ausentes | Moto, Carro, Bike, Van, Carreto | ✅ Implementado neste release |
| **C2** | Observações para o entregador ausentes | Todas de entrega | ✅ Implementado neste release |
| **C3** | MotoTáxi usa fluxo de entrega (errado) | MotoTaxi | ✅ Implementado neste release |
| **C4** | Bike sem validação de distância/peso | Bike | ✅ Implementado neste release |
| **C5** | Van/Carreto sem opção de ajudante | Van, Truck | ✅ Implementado neste release |

## GAPS ALTOS (A) — DIFERENCIAL COMPETITIVO

| # | Gap | Categorias | Status |
|---|---|---|---|
| **A1** | Valor declarado / seguro opt-in | Moto, Carro, Van | ✅ Implementado neste release |
| **A2** | Botão SOS no tracking de MotoTáxi | MotoTaxi | ✅ Implementado neste release |
| **A3** | Agendamento futuro (data/hora) | Van, Carreto | ✅ Implementado neste release |
| **A4** | Compartilhar rota (MotoTaxi) | MotoTaxi | ✅ Implementado neste release |
| **A5** | Capacidade detalhada na seleção | Van, Carreto | ✅ Implementado neste release |
| **A6** | Rename Caminhão → Carreto | Truck | ✅ Implementado neste release |

## GAPS MÉDIOS (M) — MATURIDADE DO PRODUTO

| # | Gap | Categorias | Status |
|---|---|---|---|
| **M1** | Flag de fragilidade | Moto, Carro, Van | ✅ Implementado neste release |
| **M2** | Round trip option | Carro, Van | ✅ Implementado neste release |
| **M3** | Badge Eco para Bike | Bike | ✅ Implementado neste release |
| **M4** | Aviso/ack de capacete (MotoTaxi) | MotoTaxi | ✅ Implementado neste release |
| **M5** | Tipo de carga para Van/Carreto | Van, Truck | ✅ Implementado neste release |
| **M6** | Prompt de upgrade/downgrade | Todas | ✅ Implementado (validação bike) |
| **M7** | Motorista favorito | Moto, Carro | 🔜 Próximo release |
| **M8** | Agendamento Moto/Carro | Moto, Carro | 🔜 Próximo release |
| **M9** | PIN de confirmação de entrega | Moto, Carro | 🔜 Próximo release |

---

## MUDANÇAS NO MODELO DE DADOS

### Novos campos na tabela `deliveries` (ver `MIGRATION.sql`):

```
recipient_name     text           — nome do destinatário (obrigatório no fluxo)
recipient_phone    text           — telefone do destinatário (obrigatório no fluxo)
item_description   text           — observações/instruções para o entregador
is_fragile         boolean        — flag "frágil" / "manuseie com cuidado"
declared_value     numeric(10,2)  — valor declarado para seguro
helper_count       smallint       — número de ajudantes (0, 1, 2, 3)
is_round_trip      boolean        — opção de ida e volta
scheduled_for      timestamptz    — data/hora agendada (null = imediato)
cargo_type         text           — tipo de carga: furniture/appliances/construction/other
```

---

## FLUXO DE CRIAÇÃO POR CATEGORIA (NOVO)

### Categorias de entrega (Moto / Carro / Bike / Van / Carreto)

```
Etapa 1: Veículo
  → Seleção da categoria com capacity detalhada, eco badge (bike), tag Corrida (mototaxi)

Etapa 2: Endereços
  → Coleta + Entrega + Parada extra (igual ao anterior)
  → Bike: validação distância ≤ 3km (aviso, não bloqueio)

Etapa 3: Detalhes (NOVA)
  → Nome do destinatário (obrigatório)
  → Telefone do destinatário (obrigatório)
  → Observações para o entregador (opcional)
  → Flag "Frágil" (toggle) — exceto Van/Carreto com helper
  → Valor declarado (opcional)
  → Van/Carreto: tipo de carga (Móveis/Eletro/Obra/Outros)
  → Van: helpers 0/1/2 | Carreto: helpers 0/1/2/3
  → Van/Carreto: agendamento de data/hora

Etapa 4: Confirmar
  → Resumo completo + método de pagamento
```

### MotoTáxi (fluxo completamente separado)

```
Etapa 1: Veículo (seleciona MotoTáxi)

Etapa 2: Rota
  → Origem (não "coleta") + Destino (não "entrega")
  → Estimativa de tempo e preço da corrida

Etapa 3: Segurança (NOVA)
  → Card de aviso do capacete obrigatório
  → Informação de seguro pessoal incluso
  → Confirmação de uso de capacete (checkbox obrigatório)

Etapa 4: Confirmar
  → Resumo da corrida + pagamento
  → Tracking: SOS button, Share ride button
```

---

## COMPARATIVO DE REQUISITOS DO MOTORISTA POR CATEGORIA

| Categoria | CNH | Registro | Curso | Mínimo Idade | EAR | Docs Veículo |
|---|---|---|---|---|---|---|
| Moto Entregas | A obrigatória | ❌ | Sim (Detran) | 21 anos | Obrigatório | Sim (CRLV) |
| Carro Entregas | B | ❌ | Não | 18 anos | Recomendado | Sim (CRLV) |
| Bike | Não precisa | ❌ | Não | 18 anos | Não | Não (bike) |
| MotoTáxi | A definitiva | ❌ | Sim | 21 anos | Obrigatório | Sim (CRLV) |
| Utilitário | B ou C | ❌ | Não | 18 anos | Recomendado | Sim (CRLV) |
| Carreto | B ou C | MEI recomend. | Não | 18 anos | Recomendado | Sim (CRLV) |

---

## REFERÊNCIAS

- Uber Courier Brazil: `help.uber.com` — Modalities in Brazil
- Lalamove Brazil: `lalamove.com/pt-br` — Vehicle categories, additional services
- Loggi API: `docs.api.loggi.com` — Package dimensions and shipment creation
- inDrive Couriers: `couriers.indrive.com/en-br`
- 99Moto requirements: `99app.com/motorista/categorias/99-moto`
- iFood bike courier: `institucional.ifood.com.br` — Entregas de bike
- FreteBras: `blog.fretebras.com.br` — How to publish freight
- TruckPad: `truckpad.com.br` — How it works
- Lei 12.009/2009: Regulação de motoboys no Brasil
- São Paulo mototaxi ban: `restofworld.org/2025/sao-paulo-motorcycle-ride-hailing-ban`
