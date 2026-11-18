# Gastos do Carro 🚗

App para iPhone (SwiftUI + SwiftData, iOS 17+) para controlar os gastos do seu carro.

## Funcionalidades

Visual escuro com destaque verde-limão e barra de abas flutuante.

- **Painel**: hero do carro, hodômetro em dígitos, atalhos *Atualizar KM* e *Abastecer*, consumo médio (km/l),
  estimativa de vida útil da bateria 12V e **diário de bordo** em linha do tempo
- **Central de serviços**: registre serviços com intervalo (km e/ou meses) e acompanhe os próximos vencimentos
  com alertas (em dia / em breve / vencido)
- **Documentação**: IPVA e licenciamento por ano, carimbo "EM DIA", estimativa do IPVA pela FIPE,
  além de multas, seguro e outras taxas
- **Financeiro**: gráfico de rosca por grupo, extrato por dia com busca e filtros de período; aba Resumo com
  custo por km, média mensal e gráfico dos últimos 6 meses
- **Garagem**: vários carros, com status de cada um (botão do carro, à esquerda da barra)
- **Comprovantes**: anexe foto da nota/recibo em qualquer registro
- **Leitura de cupom fiscal por foto**: valor, litros, preço, combustível, posto e data (no próprio iPhone)
- **Km por foto do painel**, além do manual
- **FIPE automática**: escolha o carro na tabela e o valor se atualiza todo mês, com gráfico de desvalorização
- **Preço médio do combustível na sua cidade** (ANP), atualizado por um robô semanal do GitHub (`data/combustivel.json`)
- **Assistente com IA da Apple** (Apple Intelligence, no aparelho): "abasteci 100 reais" e ele lança; desativado em iPhones sem suporte
- **Notificações**: serviços vencendo, IPVA, documentação pendente, bateria e lembrete semanal de atualizar o km
- **Backup e restauração** em JSON (inclui fotos), além de exportação em CSV
- **Ajustes** (botão à direita da barra): editar carro, FIPE, bateria, notificações e backup
- Dados salvos localmente no iPhone (SwiftData), sem login

## Como instalar só com Windows (sem Mac)

1. A cada `push`, o GitHub Actions compila o app num Mac na nuvem
   (aba **Actions** → build mais recente → **Artifacts** → `CarroGastos-ipa-...`).
2. Descompacte o artifact baixado para obter o `CarroGastos.ipa`.
3. Instale o **iTunes** e o **iCloud** (versões do site da Apple, não da Microsoft Store) e o **Sideloadly**.
4. Conecte o iPhone, arraste o `.ipa` no Sideloadly e entre com sua Apple ID.
5. No iPhone: ative *Ajustes → Privacidade e Segurança → Modo de Desenvolvedor* e confie no certificado em
   *Ajustes → Geral → VPN e Gerenciamento de Dispositivos*.

Com Apple ID gratuita, reinstale a cada 7 dias (os dados são mantidos). Faça backups em *Ajustes → Backup*.

## Como rodar com Mac

Você precisa de um **Mac com Xcode 16 ou mais recente**.

1. Abra `CarroGastos.xcodeproj` no Xcode.
2. Clique no projeto → target **CarroGastos** → aba **Signing & Capabilities** → em *Team*, selecione sua conta Apple
   (uma Apple ID gratuita serve; se der conflito, troque o *Bundle Identifier* para algo único, ex.: `com.seunome.CarroGastos`).
3. Para testar no simulador: escolha um iPhone na barra superior e aperte **⌘R**.
4. Para instalar no seu iPhone: conecte o cabo, selecione o aparelho e aperte **⌘R**.
   Na primeira vez, no iPhone, vá em *Ajustes → Geral → VPN e Gerenciamento de Dispositivos* e confie no seu certificado de desenvolvedor,
   e ative o *Modo de Desenvolvedor* em *Ajustes → Privacidade e Segurança*.

> Com Apple ID gratuita o app expira em 7 dias (é só rodar de novo pelo Xcode). Com o Apple Developer Program (US$ 99/ano) dura 1 ano e dá para publicar na App Store / TestFlight.

## Como o consumo médio é calculado

Método "tanque cheio a tanque cheio": entre dois abastecimentos marcados como *tanque cheio*, divide-se os km rodados pelos litros
colocados desde o último tanque cheio. Para funcionar, informe o **hodômetro** e os **litros** em cada abastecimento.

## Estrutura

```
CarroGastos/
├── CarroGastosApp.swift
├── Theme/Theme.swift           # cores, fontes e componentes visuais
├── Models/                     # Vehicle, Expense, categorias, lembretes
├── Views/
│   ├── RootView.swift          # barra flutuante + boas-vindas
│   ├── HomeView.swift          # painel
│   ├── ServicesView.swift      # central de serviços
│   ├── DocumentsView.swift     # IPVA, licenciamento, extras
│   ├── FinanceView.swift       # extrato e resumo
│   ├── GarageView.swift        # seus carros
│   ├── SettingsView.swift
│   └── Forms/                  # formulários
└── Utilities/                  # formatação R$, CSV
```

## Ideias para próximas versões

- Notificações locais para serviços e IPVA vencendo
- Foto real do carro no cartão
- Sincronização com iCloud
- Widget com gastos do mês
