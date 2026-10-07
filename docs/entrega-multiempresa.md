# Entrega multiempresa — Freitag Gestão

## O que queremos construir

Um único sistema para atender vários comércios. Cada empresa terá sua página pública, seu próprio acesso e seus próprios dados. Maicon administra os clientes e a situação do serviço; o dono do comércio administra a página, equipe e agenda.

## Fluxo previsto

1. Freitag cadastra a empresa e combina plano, prazo e forma de pagamento.
2. O responsável recebe um convite individual, com validade curta, para criar a própria conta.
3. O responsável preenche nome, logo, WhatsApp, endereço, serviços, profissionais e fotos autorizadas.
4. A página pública mostra os dados da empresa e os atalhos para WhatsApp e Google Maps.
5. O painel do responsável mostra apenas os dados da própria empresa.
6. Freitag registra o pagamento. Na primeira versão, essa mudança será manual; a cobrança automática depende da escolha de um provedor.
7. Se o serviço for suspenso, o site deixa de aceitar novos agendamentos. O responsável ainda poderá consultar e solicitar uma cópia dos próprios dados.

## Regras de segurança

- Cada registro de agenda, cliente, equipe e financeiro deverá ter um identificador da empresa.
- As regras do Supabase precisam verificar esse identificador em toda leitura e gravação.
- A situação de pagamento fica em tabela separada. A conta do dono não pode editar essa tabela.
- A tela sozinha não fará o bloqueio. O servidor e as regras do banco também precisam recusar operações de uma conta suspensa.
- Suspender não apaga o login nem o histórico. O dono deve poder consultar e exportar seus dados.
- Convites reais serão individuais, de uso único e com expiração. Não usar senha compartilhada nem enviar senha pelo WhatsApp.
- Não colocar chave secreta do Supabase no HTML. O navegador usa apenas a chave pública; o banco decide o que cada pessoa pode fazer.

## Google Maps

O endereço da empresa poderá abrir uma rota no Google Maps. Isso é um atalho de navegação, não um cadastro automático no Perfil da Empresa do Google. O dono continuará responsável por administrar o próprio perfil e poderá adicionar ali o link do site.

## Etapas de desenvolvimento

### 1. Modelo de empresas e acessos — em preparação

Criar as tabelas para empresas, responsáveis/membros e situação do serviço. O rascunho de SQL acompanha este documento. Ele não foi aplicado no Supabase.

### 2. Proteger e separar os dados atuais

Conferir qual conta é a administradora atual e vincular os registros existentes a uma empresa sem alterar horários, clientes ou valores. Depois, adicionar as regras por empresa às tabelas de agenda, profissionais e financeiro.

### 3. Ligar os painéis

Usar os dados salvos na conta para preencher a página pública. Criar cadastro/convite do responsável e configurações de logo, contato, endereço, serviços, equipe e fotos.

### 4. Cobrança e suspensão

Começar com marcação manual de pagamento. Só depois de definir provedor e preços é que se avalia cobrança automática. Testar em dados de demonstração; nunca suspender uma empresa real para testar.

### 5. Apresentação e entrega

Demonstrar o fluxo pelo celular, entregar o convite após a contratação e explicar prazo, suporte, pagamento e exportação de dados.

## Estado desta revisão

- Esta branch é uma revisão separada; não publica nem altera a versão ao vivo.
- A prévia local de entrega pode simular cadastros e suspensão, mas não autentica nem protege dados reais.
- O próximo passo técnico é revisar o SQL e mapear com segurança os dados do comércio atual antes de alterar o Supabase.
- Esta etapa ainda não conecta o formulário de agendamento ao identificador da empresa. Não mesclar como sistema multiempresa pronto.
