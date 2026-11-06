# Bootcamp Treinos API

> API desenvolvida em Node.js com Fastify e Prisma para o aplicativo Bootcamp Treinos. Ela fornece o backend necessário para gerenciar usuários, planos de treinos, estatísticas de evolução e conta com uma inteligência artificial que atua como um personal trainer virtual.

## Sobre o projeto

O backend do aplicativo de treinos é responsável pelo cadastro e gerenciamento das rotinas de atividades físicas. A API inclui geração de dados para home, gerenciamento de dados do usuário (peso, altura, % gordura), listagem e visualização de treinos e dias específicos, controle de sessões iniciadas e concluídas, assim como um endpoint integrado à IA (Google Gemini) para gerar rotinas de treino baseadas no perfil do aluno.

## Tecnologias

- **Linguagem**: TypeScript (Node.js 24.x)
- **Framework Web**: Fastify
- **Banco de Dados**: PostgreSQL
- **ORM**: Prisma (com adapter `@prisma/adapter-pg`)
- **Autenticação**: Better-Auth (Social login via Google)
- **Validação e Tipagem**: Zod (integrado ao fastify-type-provider-zod)
- **Documentação de API**: @scalar/fastify-api-reference e @fastify/swagger
- **IA/LLM**: Vercel AI SDK e provedor do Google Generative AI (`gemini-2.5-flash`)

## Arquitetura e Estrutura do projeto

O projeto utiliza um padrão simplificado baseado em "Use Cases", mantendo a responsabilidade de roteamento e injeção de dependência na camada de Rotas (Controllers). 

- `prisma/`: Configuração do banco de dados (schema.prisma).
- `src/`
  - `errors/`: Definições customizadas de erro (ex: `NotFoundError`, `SessionAlreadyStartedError`).
  - `lib/`: Configurações de serviços externos e bibliotecas centrais (banco de dados, autenticação e validação de env).
  - `routes/`: Declaração dos endpoints e esquemas de validação (Fastify + Zod).
  - `schemas/`: Esquemas de dados para entrada e saída utilizando Zod.
  - `usecases/`: Lógica de negócio da aplicação (ex: `CreateWorkoutPlan`, `StartWorkoutSession`).

**Fluxo geral da aplicação:**
`Cliente HTTP → Endpoint (Fastify com Zod Schema) → Auth Check → Use Case (Regra de Negócio) → Repository (Prisma) → PostgreSQL`

**Fluxo da Inteligência Artificial:**
`Cliente HTTP → Endpoint /ai → Vercel AI SDK (via Google Gemini) → [Invocação de Tool se necessário] → Use Case → Resposta em Stream`

## Autenticação

A API utiliza a biblioteca **Better-Auth** em conjunto com a tabela `Session` e `Account` do Prisma.
A autenticação primária configurada é o **Google Social Login**. 
O gerenciamento da sessão ocorre por **Cookies** seguros definidos automaticamente pelas rotas nativas criadas pelo better-auth (`/api/auth/*`).

* Todos os endpoints da aplicação (com exceção da raiz `/` e da página `/docs`) exigem que o usuário esteja autenticado e tenha um cookie de sessão válido (`sessionToken`).

## Endpoints

### Home

#### Obter dados da Home
**Request**
```http
GET /home/:date
```
- Path Params:
  - `date`: Data em formato ISO (ex: `2026-09-30`)

**Response**
Retorna o plano ativo, o treino programado para o dia, sequência de treinos (streak) e consistência diária.

```json
{
  "activeWorkoutPlanId": "uuid",
  "todayWorkoutDay": {
    "id": "uuid",
    "workoutPlanId": "uuid",
    "name": "Peito e Tríceps",
    "isRest": false,
    "weekDay": "MONDAY",
    "estimatedDurationInSeconds": 3600,
    "coverImageUrl": "https://...",
    "exercisesCount": 6
  },
  "workoutStreak": 3,
  "consistencyByDay": {
    "2026-09-30T00:00:00.000Z": {
      "workoutDayCompleted": true,
      "workoutDayStarted": true
    }
  }
}
```
**Status codes**
| Código | Descrição |
| ------ | --------- |
| 200    | Sucesso   |
| 401    | Unauthorized |
| 404    | Not Found |
| 500    | Internal Server Error |

---

### Me (Usuário)

#### Visualizar perfil do usuário
**Request**
```http
GET /me
```
**Response**
```json
{
  "userId": "uuid",
  "userName": "João",
  "weightInGrams": 75000,
  "heightInCentimeters": 178,
  "age": 25,
  "bodyFatPercentage": 15
}
```
(Retorna `null` se os dados do corpo/treino ainda não estiverem cadastrados).

#### Atualizar dados do usuário
**Request**
```http
PUT /me
```
**Body**
```json
{
  "weightInGrams": 75000,
  "heightInCentimeters": 178,
  "age": 25,
  "bodyFatPercentage": 15
}
```

---

### Stats

#### Visualizar estatísticas do usuário
**Request**
```http
GET /stats?from=2026-09-01T00:00:00Z&to=2026-09-30T23:59:59Z
```
- Query Params: `from` e `to` (ambos em formato ISO date).

**Response**
```json
{
  "workoutStreak": 5,
  "consistencyByDay": { ... },
  "completedWorkoutsCount": 12,
  "conclusionRate": 85.5,
  "totalTimeInSeconds": 43200
}
```

---

### Planos de Treino (Workout Plans)

#### Listar planos
**Request**
```http
GET /workout-plans?active=true
```
- Query Params: `active` (opcional, `true` ou `false`).

#### Criar novo plano (Pode ser invocado pela IA)
**Request**
```http
POST /workout-plans
```
**Body**
```json
{
  "name": "Projeto Verão",
  "workoutDays": [
    {
      "name": "Treino A - Peito",
      "weekDay": "MONDAY",
      "isRest": false,
      "estimatedDurationInSeconds": 3600,
      "coverImageUrl": "https://...",
      "exercises": [
        {
          "order": 1,
          "name": "Supino Reto",
          "sets": 4,
          "reps": 10,
          "restTimeInSeconds": 60
        }
      ]
    }
  ]
}
```

#### Iniciar Sessão de Treino
**Request**
```http
POST /workout-plans/:workoutPlanId/days/:workoutDayId/sessions
```
**Response (201)**
```json
{
  "userWorkoutSessionId": "uuid"
}
```
*Gera erro 422 se o plano não estiver ativo e 409 se já houver uma sessão iniciada no dia.*

#### Finalizar Sessão de Treino
**Request**
```http
PATCH /workout-plans/:workoutPlanId/days/:workoutDayId/sessions/:sessionId
```
**Body**
```json
{
  "completedAt": "2026-09-30T10:30:00Z"
}
```

---

### Inteligência Artificial

#### Conversar com Personal Trainer IA
**Request**
```http
POST /ai
```
**Body**
```json
{
  "messages": [
    {
      "role": "user",
      "content": "Gostaria de criar um treino de 4 dias na semana."
    }
  ]
}
```
*A resposta deste endpoint é um Stream de texto gerenciado pelo Vercel AI SDK, retornando chunks no formato UIMessage.*

---

## Tratamento de erros

A API retorna um objeto padrão quando ocorre alguma exceção previsível. O modelo de erro é:
```json
{
  "error": "Mensagem descritiva do erro",
  "code": "CODIGO_DO_ERRO"
}
```

Status Codes comuns utilizados na aplicação:
- `200 / 201` - Sucesso
- `400` - Bad Request (Erros de validação Zod no formato da requisição)
- `401` - Unauthorized (Ausência de sessão)
- `404` - Not Found (`NOT_FOUND_ERROR`)
- `409` - Conflict (`SESSION_ALREADY_STARTED_ERROR`)
- `422` - Unprocessable Entity (`WORKOUT_PLAN_NOT_ACTIVE_ERROR`)
- `500` - Internal Server Error (`INTERNAL_SERVER_ERROR`)

---

## Banco de dados

O schema principal consiste nas tabelas:
- `User`: Cadastro base e chaves da autenticação.
- `Session` / `Account` / `Verification`: Tabelas auxiliares do `better-auth`.
- `WorkoutPlan`: Planos de treino atrelados ao usuário (relacionamento 1:N).
- `WorkoutDay`: Os dias da semana vinculados ao plano (MONDAY a SUNDAY), com o atributo `isRest` indicando se há treino naquele dia.
- `WorkoutExercise`: Exercícios detalhados pertencentes a um dia (`WorkoutDay`).
- `WorkoutSession`: Marca as instâncias reais em que um usuário executou um `WorkoutDay`, guardando as datas de início e fim (`startedAt`, `completedAt`).

---

## Variáveis de ambiente

Essas são as variáveis esperadas no arquivo `.env`. Os dados não devem ser comitados.

- `PORT` = Porta da API (Padrão: 3001)
- `DATABASE_URL` = URL de conexão com o PostgreSQL (Ex: `postgresql://postgres:password@localhost:5432/bootcamp-treinos-api`)
- `API_BASE_URL` = URL em que a API está rodando
- `WEB_APP_BASE_URL` = URL em que o Frontend está rodando, necessário para CORS. (Ex: `http://localhost:3000`)
- `BETTER_AUTH_SECRET` = Chave secreta de encriptação dos cookies e JWT do Auth.
- `BETTER_AUTH_URL` = URL da API para base do Auth (Ex: `http://localhost:3001`)
- `GOOGLE_CLIENT_ID` = ID do projeto Google (OAuth)
- `GOOGLE_CLIENT_SECRET` = Segredo do cliente Google (OAuth)
- `GOOGLE_GENERATIVE_AI_API_KEY` = API Key da sua conta no Google AI Studio (Gemini).

---

## Como executar localmente

1. **Clone o repositório**
   ```bash
   git clone <URL_DO_REPOSITORIO>
   cd fit-ia-api
   ```

2. **Instale as dependências**
   ```bash
   npm install
   ```

3. **Configuração de Variáveis**
   - Crie um arquivo `.env` baseado no `.env.example`.
   - Preencha com os valores locais, especialmente as chaves do Google.

4. **Inicie o Banco de Dados (Docker)**
   Para subir a base Postgres local:
   ```bash
   docker-compose up -d
   ```

5. **Ações do Prisma**
   Suba as tabelas no banco de dados através das migrações e gere os tipos do client:
   ```bash
   npx prisma migrate dev
   npx prisma generate
   ```

6. **Execute o projeto (Modo de desenvolvimento)**
   ```bash
   npm run dev
   ```

7. **Acesso e Documentação Interativa**
   A API conta com a biblioteca Scalar para documentar Swagger de forma visual.
   - Acesse: `http://localhost:3001/docs` no seu navegador para ver todos os esquemas e testar endpoints.

---

## Possíveis limitações

- O AI Chat é totalmente processado do lado do servidor (Server-Side) na rota POST e bloqueia conexões do usuário que não mandem o payload correto das `UIMessages`.
- As restrições de permissões estão baseadas exclusivamente no `userId` da sessão atual. Acesso à entidades criadas sempre confere se o elemento pertence ao usuário na hora de fazer updates.

## Melhorias futuras (Sugestões Técnicas)

- **Testes Automatizados:** O projeto não possui uma camada robusta de testes unitários ou de integração (Jest ou Vitest).
- **Paginação:** Na listagem de planos (`GET /workout-plans`), embora possivelmente sejam poucos planos por usuário, implementar paginação garante que não ocorra um overfetching futuramente.
- **Isolamento da Integração AI:** Poderia haver uma classe abstrata de IA no use case, deixando o router `ai.ts` com menos código bruto do Prompt e Definição de Tool.
- **Cache:** Utilizar Redis ou cache local em rotas constantes como `/stats` para evitar sobrecarga no banco de dados.
# 🏋️ Fit-IA API

API inteligente para geração e gerenciamento de planos de treino personalizados utilizando Inteligência Artificial.

## 📖 Sobre o Projeto

O Fit-IA é uma API desenvolvida para auxiliar usuários na criação de treinos personalizados com base em seus objetivos, nível de experiência e informações físicas.

A aplicação utiliza IA Generativa para interpretar dados do usuário e criar planos de treino estruturados automaticamente.

---

## 🚀 Tecnologias Utilizadas

### Backend
- Node.js
- TypeScript
- Fastify

### Banco de Dados
- PostgreSQL
- Prisma ORM

### Inteligência Artificial
- Google Gemini
- AI SDK

### Autenticação
- Better Auth

### Documentação
- Swagger
- Scalar API Reference

### DevOps
- Docker
- Docker Compose

### Validação
- Zod

---

## 🏗️ Arquitetura

```text
src/
├── routes/         # Rotas da aplicação
├── usecases/       # Regras de negócio
├── schemas/        # Validação de dados
├── lib/            # Configurações e integrações
├── errors/         # Tratamento de erros
└── server.ts       # Inicialização da API
```

A aplicação segue uma arquitetura baseada em Casos de Uso (Use Cases), promovendo maior organização e facilidade de manutenção.

---

## ⚙️ Funcionalidades

### 👤 Usuários
- Cadastro de usuário
- Login
- Autenticação

### 🏋️ Treinos
- Criação de plano de treino
- Listagem de treinos
- Atualização de treinos
- Estatísticas do usuário

### 🤖 IA
- Geração automática de planos de treino
- Personalização baseada em objetivos
- Atualização dinâmica de informações do usuário

### 📄 Documentação
- Swagger UI
- Scalar API Reference

---

## 📦 Instalação

### Clonar o repositório

```bash
git clone https://github.com/devantonio27/Fit-ia.git
```

```bash
cd Fit-ia
```

### Instalar dependências

```bash
npm install
```

### Configurar variáveis de ambiente

Crie um arquivo `.env`:

```env
DATABASE_URL=
GEMINI_API_KEY=
BETTER_AUTH_SECRET=
BETTER_AUTH_URL=
```

---

## 🐳 Executando com Docker

```bash
docker compose up -d
```

---

## 🗄️ Executando as migrations

```bash
npx prisma migrate dev
```

---

## ▶️ Executando o projeto

Modo desenvolvimento:

```bash
npm run dev
```

Modo produção:

```bash
npm run build
npm start
```

---

## 📚 Documentação da API

Após iniciar a aplicação:

Swagger:

```bash
http://localhost:3333/docs
```

Scalar:

```bash
http://localhost:3333/reference
```

---

## 🔗 Principais Endpoints

### Usuários

```http
POST /users
```

```http
POST /login
```

---

### Treinos

```http
POST /workout-plan
```

```http
GET /workout-plan
```

```http
GET /stats
```

---

### IA

```http
POST /ai/chat
```

---

## 💡 Motivação

Este projeto foi desenvolvido com o objetivo de aprofundar conhecimentos em:

- Arquitetura Backend
- TypeScript
- Fastify
- Prisma ORM
- PostgreSQL
- Docker
- Inteligência Artificial Generativa
- Integração com APIs modernas

---

## 📈 Próximos Passos

- [ ] Testes unitários
- [ ] Testes de integração
- [ ] CI/CD com GitHub Actions
- [ ] Deploy em produção
- [ ] Monitoramento e logs
- [ ] Frontend em React

---

## 👨‍💻 Autor

Desenvolvido por **Antonio Carlos**

- GitHub: https://github.com/devantonio27
- LinkedIn: adicionar link

---

## 📄 Licença

Este projeto está sob a licença MIT.
