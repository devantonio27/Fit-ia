# 🔍 Revisão Geral — fit-ia-api

## Visão Geral do Projeto

API backend para um aplicativo de treinos com chat de IA integrado (personal trainer virtual). Stack principal:

| Componente | Tecnologia |
|---|---|
| Runtime | Node.js 24 |
| Linguagem | TypeScript (strict mode) |
| Framework HTTP | Fastify 5 |
| ORM | Prisma 7 (client gerado + adapter pg) |
| Banco de dados | PostgreSQL (Neon em prod, Docker local) |
| Autenticação | better-auth (OAuth Google) |
| IA | Vercel AI SDK + Google Gemini 2.5 Flash |
| Validação | Zod 4 |
| Documentação | Swagger + Scalar API Reference |
| Containerização | Docker multi-stage |

**Estrutura de diretórios:**
```
src/
├── index.ts              # Entry point + server setup
├── errors/index.ts       # Custom error classes
├── generated/prisma/     # Prisma generated client
├── lib/
│   ├── auth.ts           # better-auth config
│   ├── db.ts             # Prisma client singleton
│   └── env.ts            # Env validation via Zod
├── routes/
│   ├── ai.ts             # Chat com IA
│   ├── home.ts           # Dados da tela inicial
│   ├── me.ts             # Perfil/dados do usuário
│   ├── stats.ts          # Estatísticas
│   └── workout-plan.ts   # CRUD de planos de treino
├── schemas/index.ts      # Zod schemas (request/response)
└── usecases/
    ├── CreateWorkoutPlan.ts
    ├── GetHomeData.ts
    ├── GetStats.ts
    ├── GetUserTrainData.ts
    ├── GetWorkoutDay.ts
    ├── GetWorkoutPlan.ts
    ├── ListWorkoutPlan.ts
    ├── StartWorkoutSession.ts
    ├── UpdateWorkoutSession.ts
    └── UpsertUserTrainData.ts
```

---

## ✅ O que está bem implementado

### 1. Validação de ambiente com Zod
A validação de variáveis de ambiente em [env.ts](file:///d:/Projetos/fit-ia-api/src/lib/env.ts) é excelente — fail-fast na inicialização com mensagens claras de erro. Padrão maduro.

### 2. Separação Routes ↔ UseCases
Boa separação de responsabilidades. As routes lidam com HTTP (request/reply), e os usecases contêm a lógica de negócio. Os DTOs de input/output em cada usecase criam contratos claros.

### 3. Schemas Zod bem estruturados
[schemas/index.ts](file:///d:/Projetos/fit-ia-api/src/schemas/index.ts) usa Zod com `fastify-type-provider-zod` para validação automática de request e tipagem de response no Swagger. Aproveitamento correto do enum `WeekDay` gerado pelo Prisma.

### 4. Documentação da API
Swagger + Scalar API Reference com duas fontes (app + auth) é uma boa configuração para DX. OperationIds e tags bem definidos nas rotas.

### 5. Tratamento de erros com classes customizadas
[errors/index.ts](file:///d:/Projetos/fit-ia-api/src/errors/index.ts) define erros de domínio (`NotFoundError`, `WorkoutPlanNotActiveError`, `SessionAlreadyStartedError`) que são mapeados para HTTP status codes corretos nas routes.

### 6. Docker multi-stage
O [Dockerfile](file:///d:/Projetos/fit-ia-api/Dockerfile) com 3 estágios (base → deps → build → production) é eficiente e separa corretamente dependências de dev/prod.

### 7. Singleton do Prisma Client
O padrão em [db.ts](file:///d:/Projetos/fit-ia-api/src/lib/db.ts) com `globalForPrisma` evita múltiplas instâncias em hot-reload durante dev. Padrão bem conhecido e correto.

### 8. Prompt de IA bem elaborado
O system prompt em [ai.ts](file:///d:/Projetos/fit-ia-api/src/routes/ai.ts) é detalhado, com personalidade, regras de interação, divisões de treino e URLs de imagens de capa. Demonstra boa compreensão do domínio.

### 9. CORS restritivo
Configuração de CORS limitada ao `WEB_APP_BASE_URL` com credentials. Não é `origin: *`.

### 10. Transação na criação de plano
[CreateWorkoutPlan.ts](file:///d:/Projetos/fit-ia-api/src/usecases/CreateWorkoutPlan.ts) usa `prisma.$transaction` para desativar o plano anterior e criar o novo atomicamente.

---

## 🔴 Problemas Encontrados

---

### P1 — Credenciais reais expostas no `.env.example`

**Problema:** O arquivo [.env.example](file:///d:/Projetos/fit-ia-api/.env.example) contém o que parecem ser chaves reais do Google OAuth (`GOCSPX-...`), API key do Gemini (`AIzaSy...`), e secret do better-auth. Além disso, o `.env.example` está listado no `.gitignore`, ou seja, **o template de exemplo sequer é versionado**, mas as credenciais reais do `.env` de produção (com a connection string do Neon) estão no repositório local sem proteção clara.

**Local:** [.env.example](file:///d:/Projetos/fit-ia-api/.env.example), [.env](file:///d:/Projetos/fit-ia-api/.env), [.gitignore](file:///d:/Projetos/fit-ia-api/.gitignore)

**Impacto:** 🔴 **Alto** — Vazamento de credenciais. Se o `.env.example` com chaves reais for commitado, é comprometimento direto.

**Sugestão:**
- Remover todas as credenciais reais do `.env.example` e colocar apenas placeholders descritivos
- Remover `.env.example` do `.gitignore` (ele **deveria** ser versionado, mas sem segredos)
- Garantir que `.env` permaneça no `.gitignore`
- Rotacionar todas as chaves que já foram expostas

---

### P2 — Autenticação repetida e não centralizada (boilerplate massivo)

**Problema:** Cada handler faz a mesma chamada de autenticação manualmente:
```ts
const session = await auth.api.getSession({
  headers: fromNodeHeaders(request.headers),
});
if (!session) {
  return reply.status(401).send({ error: "Unauthorized", code: "UNAUTHORIZED" });
}
```
Esse bloco se repete **idêntico** em ~10 handlers.

**Local:** Todos os arquivos em [routes/](file:///d:/Projetos/fit-ia-api/src/routes)

**Impacto:** 🟡 **Médio** — Código duplicado, fácil de esquecer em rotas futuras, difícil de manter se a lógica de autenticação mudar.

**Sugestão:** Criar um Fastify `preHandler` hook ou plugin de autenticação que injete `session` na `request` automaticamente. Exemplo:
```ts
app.addHook('preHandler', async (request, reply) => {
  const session = await auth.api.getSession({ headers: fromNodeHeaders(request.headers) });
  if (!session) return reply.status(401).send({ error: "Unauthorized", code: "UNAUTHORIZED" });
  request.session = session;
});
```

---

### P3 — Tratamento de erros repetido sem error handler global

**Problema:** Cada handler tem seu próprio `try/catch` com mapeamento manual de erros para HTTP status codes. O padrão `if (error instanceof X) → status(Y)` se repete em quase todos os handlers.

**Local:** Todos os arquivos em [routes/](file:///d:/Projetos/fit-ia-api/src/routes)

**Impacto:** 🟡 **Médio** — Duplicação, risco de inconsistência (uma rota pode tratar um erro diferente de outra), e handlers inflados.

**Sugestão:** Usar `app.setErrorHandler()` do Fastify para centralizar o mapeamento erro → HTTP response:
```ts
app.setErrorHandler((error, request, reply) => {
  if (error instanceof NotFoundError) return reply.status(404).send({...});
  if (error instanceof WorkoutPlanNotActiveError) return reply.status(422).send({...});
  // ...fallback 500
});
```

---

### P4 — Bug na query de `CreateWorkoutPlan`: falta filtro de `userId`

**Problema:** A busca pelo plano ativo existente em [CreateWorkoutPlan.ts:46-50](file:///d:/Projetos/fit-ia-api/src/usecases/CreateWorkoutPlan.ts#L46-L50) não filtra por `userId`:
```ts
const existingWorkoutPlan = await prisma.workoutPlan.findFirst({
  where: { isActive: true }, // ← falta userId!
});
```
Isso significa que criar um plano de treino pode **desativar o plano ativo de outro usuário**.

**Local:** [CreateWorkoutPlan.ts](file:///d:/Projetos/fit-ia-api/src/usecases/CreateWorkoutPlan.ts) — linha 46

**Impacto:** 🔴 **Alto** — Bug de negócio com potencial de corromper dados de outros usuários.

**Sugestão:** Adicionar `userId: dto.userId` no `where`.

---

### P5 — Bug na `StartWorkoutSession`: verificação de sessão existente muito ampla

**Problema:** Em [StartWorkoutSession.ts:44-46](file:///d:/Projetos/fit-ia-api/src/usecases/StartWorkoutSession.ts#L44-L46), a verificação bloqueia novas sessões para sempre:
```ts
const existingSession = await prisma.workoutSession.findFirst({
  where: { workoutDayId: dto.workoutDayId }, // sem filtro de data!
});
```
Uma vez que o usuário inicia uma sessão para um dia, ele **nunca mais poderá iniciar outra** naquele dia da semana, mesmo em semanas futuras.

**Local:** [StartWorkoutSession.ts](file:///d:/Projetos/fit-ia-api/src/usecases/StartWorkoutSession.ts) — linha 44

**Impacto:** 🔴 **Alto** — Bug que impede o uso normal da aplicação após a primeira semana.

**Sugestão:** Filtrar por data (ex: sessões iniciadas no mesmo dia) ou por sessões incompletas (`completedAt: null`).

---

### P6 — Rota de IA sem validação de body e sem schema de request

**Problema:** Em [ai.ts:81-84](file:///d:/Projetos/fit-ia-api/src/routes/ai.ts#L81-L84), o schema da rota POST `/ai/` não define `body`, e o handler faz um cast inseguro:
```ts
const { messages } = request.body as { messages: UIMessage[] };
```
Qualquer payload pode ser enviado sem validação.

**Local:** [routes/ai.ts](file:///d:/Projetos/fit-ia-api/src/routes/ai.ts) — linhas 81-95

**Impacto:** 🟡 **Médio** — Entrada não validada pode causar erros inesperados ou comportamento indesejado. Quebra a consistência com o resto da API que valida tudo via Zod.

**Sugestão:** Definir um Zod schema para o body do chat (ao menos `z.object({ messages: z.array(...) })`).

---

### P7 — Instanciação de usecases dentro dos handlers (sem injeção de dependência)

**Problema:** Cada handler instancia os usecases diretamente com `new`:
```ts
const createWorkoutPlan = new CreateWorkoutPlan();
const result = await createWorkoutPlan.execute({...});
```
Os usecases acessam o `prisma` client diretamente via import. Isso não é um problema crítico na escala atual, mas torna impossível fazer testes unitários sem mockar imports.

**Local:** Todos os handlers e usecases.

**Impacto:** 🟢 **Baixo** — Funcional, mas dificulta testabilidade e evolução.

**Sugestão:** Para o futuro, considerar injeção do repositório/prisma via construtor dos usecases.

---

### P8 — `calculateStreak` duplicado entre `GetHomeData` e `GetStats`

**Problema:** O método `calculateStreak` existe de forma quase idêntica em [GetHomeData.ts:134-188](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts#L134-L188) e [GetStats.ts:117-169](file:///d:/Projetos/fit-ia-api/src/usecases/GetStats.ts#L117-L169). A diferença é que em `GetHomeData` os dias de descanso incrementam o streak, e em `GetStats` não.

**Local:** [GetHomeData.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts), [GetStats.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetStats.ts)

**Impacto:** 🟡 **Médio** — Duplicação de lógica complexa. Uma correção em um pode não ser replicada no outro.

**Sugestão:** Extrair para um módulo compartilhado (ex: `src/domain/calculateStreak.ts`) com um parâmetro para controlar se dias de descanso contam.

---

### P9 — `WEEKDAY_MAP` duplicado

**Problema:** O mapeamento `WEEKDAY_MAP` é definido identicamente em [GetHomeData.ts:9-17](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts#L9-L17) e [GetStats.ts:9-17](file:///d:/Projetos/fit-ia-api/src/usecases/GetStats.ts#L9-L17).

**Local:** Mesmos arquivos acima.

**Impacto:** 🟢 **Baixo** — Duplicação simples.

**Sugestão:** Mover para um utilitário compartilhado.

---

### P10 — Ausência total de testes

**Problema:** Não há nenhum arquivo de teste, framework de testes configurado, ou script de teste no `package.json`.

**Local:** Projeto inteiro.

**Impacto:** 🟡 **Médio** — Qualquer refatoração futura é arriscada sem rede de segurança. Os bugs P4 e P5 provavelmente teriam sido pegos com testes.

**Sugestão:** Começar com testes de integração dos usecases mais críticos (CreateWorkoutPlan, StartWorkoutSession) usando Vitest.

---

### P11 — Erro no `docker-compose.yml`: variável de ambiente com hífen

**Problema:** Em [docker-compose.yml:6](file:///d:/Projetos/fit-ia-api/docker-compose.yml#L6):
```yaml
POSTGRES-USER: postgres  # ← deveria ser POSTGRES_USER (underline)
```
O hífen torna a variável inválida. O Postgres pode não reconhecer o usuário configurado.

**Local:** [docker-compose.yml](file:///d:/Projetos/fit-ia-api/docker-compose.yml)

**Impacto:** 🟡 **Médio** — O container pode iniciar com o usuário padrão (`postgres`) por coincidência, mascarando o bug, mas em cenários diferentes pode falhar.

**Sugestão:** Corrigir para `POSTGRES_USER`.

---

### P12 — `dayjs.extend(utc)` chamado em múltiplos arquivos

**Problema:** `dayjs.extend(utc)` é chamado no topo de [GetHomeData.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts#L7), [GetStats.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetStats.ts#L7) e [GetWorkoutDay.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetWorkoutDay.ts#L8). É idempotente então não causa bug, mas é ruído.

**Local:** 3 usecases.

**Impacto:** 🟢 **Baixo** — Funcional, mas desorganizado.

**Sugestão:** Centralizar `dayjs` configurado (com plugins) em `lib/dayjs.ts` e importar de lá.

---

### P13 — `git-filter-repo` como dependência de produção

**Problema:** O pacote `git-filter-repo` está listado em `dependencies` do [package.json](file:///d:/Projetos/fit-ia-api/package.json#L42). Esse pacote é uma ferramenta de manutenção do Git e não deveria estar no bundle de produção.

**Local:** [package.json](file:///d:/Projetos/fit-ia-api/package.json) — linha 42

**Impacto:** 🟢 **Baixo** — Peso desnecessário na imagem Docker, mas sem impacto funcional.

**Sugestão:** Remover ou mover para `devDependencies`.

---

### P14 — Código comentado e anotações de debug na autenticação

**Problema:** Em [auth.ts](file:///d:/Projetos/fit-ia-api/src/lib/auth.ts), há código comentado (linhas 41-46) e um comentário `// remove isso` na linha 14 que indica configuração temporária que ficou no código.

**Local:** [auth.ts](file:///d:/Projetos/fit-ia-api/src/lib/auth.ts) — linhas 14, 41-46

**Impacto:** 🟢 **Baixo** — Ruído no código. Mas o `crossSubDomainCookies: { enabled: false }` com o comentário "remove isso" pode indicar que a configuração de cookies precisa ser revisada para produção.

**Sugestão:** Limpar código comentado e resolver a configuração de cookies.

---

### P15 — `GetHomeData` traz todos os exercícios e sessões sem necessidade

**Problema:** Em [GetHomeData.ts:52-58](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts#L52-L58), o include traz `exercises` e `sessions` de todos os workout days, mas o resultado final só usa `exercises.length` do dia de hoje. É um overfetching do banco.

**Local:** [GetHomeData.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts)

**Impacto:** 🟡 **Médio** — Performance degradada conforme o volume de dados cresce. Dados desnecessários sendo transferidos do banco.

**Sugestão:** Usar `_count` para exercícios (como já feito em `GetWorkoutPlan`) e buscar sessões separadamente com filtro de data.

---

### P16 — Rota home com URL estranha: `/home/home/:date`

**Problema:** O prefixo da rota é `/home` (registrado em [index.ts:85](file:///d:/Projetos/fit-ia-api/src/index.ts#L85)) e a URL interna é `/home/:date` ([home.ts:14](file:///d:/Projetos/fit-ia-api/src/routes/home.ts#L14)), resultando na URL final `/home/home/:date`.

**Local:** [routes/home.ts](file:///d:/Projetos/fit-ia-api/src/routes/home.ts), [index.ts](file:///d:/Projetos/fit-ia-api/src/index.ts#L85)

**Impacto:** 🟡 **Médio** — URL redundante e confusa na API pública.

**Sugestão:** Mudar a URL interna para `/:date` (já que o prefixo `/home` é aplicado no registro).

---

### P17 — Sem rate limiting na rota de IA

**Problema:** A rota POST `/ai/` faz streaming de chamadas ao Gemini sem nenhum rate limit. Um usuário autenticado pode fazer centenas de requests por segundo, gerando custos significativos na API do Google.

**Local:** [routes/ai.ts](file:///d:/Projetos/fit-ia-api/src/routes/ai.ts)

**Impacto:** 🟡 **Médio** — Potencial de abuso e custos inesperados.

**Sugestão:** Implementar rate limiting por usuário (ex: `@fastify/rate-limit`), especialmente na rota de IA.

---

### P18 — Histórico de chat não é persistido no backend

**Problema:** A rota de IA recebe `messages` do frontend a cada request. Não há persistência de conversas no banco. Se o frontend perder o estado, o histórico é perdido. Isso também significa que o frontend controla o que é enviado como contexto — um usuário técnico poderia manipular o histórico.

**Local:** [routes/ai.ts](file:///d:/Projetos/fit-ia-api/src/routes/ai.ts)

**Impacto:** 🟢 **Baixo** (por enquanto) — Aceitável para MVP, mas limitante para features futuras (ex: ver conversas anteriores).

**Sugestão:** Considerar persistir conversas no banco futuramente.

---

---

## 📊 Resumo Executivo

### 1. O que está bom
- Stack moderna e coesa (Fastify + Prisma + Zod + AI SDK)
- Validação de ambiente com fail-fast
- Separação Routes ↔ UseCases com DTOs claros
- Documentação API automática com Swagger/Scalar
- Docker multi-stage funcional
- Prompt de IA bem detalhado e com boas regras de negócio
- CORS restritivo
- Transações onde necessário
- Schemas de validação robustos com Zod

### 2. Principais problemas encontrados

| # | Problema | Impacto |
|---|---|---|
| **P4** | `CreateWorkoutPlan` pode desativar plano de outro usuário (falta `userId` no where) | 🔴 Alto |
| **P5** | `StartWorkoutSession` bloqueia permanentemente novas sessões (falta filtro de data) | 🔴 Alto |
| **P1** | Credenciais reais no `.env.example` | 🔴 Alto |
| **P2** | Auth duplicada em todos os handlers (~10x) | 🟡 Médio |
| **P3** | Error handling duplicado sem handler global | 🟡 Médio |
| **P6** | Rota de IA sem validação de body | 🟡 Médio |
| **P8** | `calculateStreak` duplicado com comportamento sutilmente diferente | 🟡 Médio |
| **P11** | Erro no docker-compose (POSTGRES-USER vs POSTGRES_USER) | 🟡 Médio |
| **P16** | URL da home duplicada (`/home/home/:date`) | 🟡 Médio |

### 3. Possíveis gargalos

| Gargalo | Local | Risco |
|---|---|---|
| **Overfetching no GetHomeData** — traz exercises + sessions de todos os dias quando só precisa do dia atual | [GetHomeData.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts) | Médio (cresce com dados) |
| **calculateStreak varre até 365 dias** — com query extra ao banco a cada chamada | [GetHomeData.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetHomeData.ts), [GetStats.ts](file:///d:/Projetos/fit-ia-api/src/usecases/GetStats.ts) | Baixo (aceitável hoje) |
| **Sem rate limit no chat IA** — custos podem escalar | [routes/ai.ts](file:///d:/Projetos/fit-ia-api/src/routes/ai.ts) | Médio (financeiro) |
| **Sem paginação na listagem de planos** — lista tudo com days + exercises | [ListWorkoutPlan.ts](file:///d:/Projetos/fit-ia-api/src/usecases/ListWorkoutPlan.ts) | Baixo (poucos planos por user) |

### 4. O que melhorar primeiro (prioridade alta)

1. **🔴 Corrigir P4** — Adicionar `userId` na busca do plano ativo em `CreateWorkoutPlan` (1 linha)
2. **🔴 Corrigir P5** — Corrigir lógica de verificação de sessão existente em `StartWorkoutSession` (filtrar por data ou completedAt)
3. **🔴 Corrigir P1** — Limpar credenciais do `.env.example`, rotacionar chaves expostas
4. **🟡 Corrigir P11** — Fix do docker-compose (`POSTGRES_USER`)
5. **🟡 Corrigir P16** — Fix da URL duplicada da home

### 5. O que pode ficar para depois

- **P2 + P3**: Middleware de auth + error handler global (refatoração de qualidade)
- **P6**: Schema do body da rota de IA
- **P7**: Injeção de dependência nos usecases
- **P8 + P9 + P12**: Extrair utilitários compartilhados (calculateStreak, WEEKDAY_MAP, dayjs)
- **P10**: Setup de testes
- **P13**: Limpar `git-filter-repo` das dependencies
- **P14**: Limpar código comentado e resolver config de cookies
- **P15**: Otimizar query do GetHomeData
- **P17**: Rate limiting
- **P18**: Persistência de chat

> [!IMPORTANT]
> Os bugs P4 e P5 são críticos e devem ser corrigidos antes de qualquer deploy para produção real. São bugs de integridade de dados que afetam diretamente a experiência do usuário.
