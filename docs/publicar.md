# Como publicar o Auto Check na App Store (sem Mac)

O GitHub monta, assina e envia o app sozinho. Você faz só a parte das contas, uma vez.

## 1. Conta Apple Developer (obrigatória, US$ 99/ano)
1. Acesse developer.apple.com/programs e faça a inscrição com sua Apple ID.
2. Depois de aprovado, anote o **Team ID** (developer.apple.com → Account → Membership).

## 2. Criar o app no App Store Connect
1. appstoreconnect.apple.com → **Apps** → **+** → **Novo app**.
2. Plataforma iOS · Nome: **Auto Check: Gastos do Carro** · Idioma: Português (Brasil).
3. **Bundle ID**: registre um em developer.apple.com → Identifiers (ex.: `com.seunome.autocheck`).
   - Se usar um diferente de `com.meuapp.CarroGastos`, crie no GitHub a variável **BUNDLE_ID**
     (Settings → Secrets and variables → Actions → aba Variables).
4. SKU: qualquer código, ex.: `autocheck001`.

## 3. Chave de API (para o GitHub enviar o app por você)
1. App Store Connect → **Usuários e Acesso** → **Integrações** → **Chaves de API do App Store Connect** → **+**.
2. Nome: GitHub · Acesso: **App Manager**. Baixe o arquivo **.p8** (só dá para baixar uma vez).
3. Anote o **Key ID** e o **Issuer ID** mostrados na página.

## 4. Colocar os dados no GitHub (Secrets)
No repositório → **Settings → Secrets and variables → Actions → New repository secret**:

| Nome | Valor |
|---|---|
| `APPLE_TEAM_ID` | seu Team ID |
| `ASC_KEY_ID` | Key ID da chave |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | abra o .p8 num editor de texto e cole o conteúdo inteiro |

Esses dados ficam criptografados no GitHub; ninguém consegue ver, nem em repositório público.

## 5. Enviar
1. GitHub → **Actions** → **Publicar no TestFlight / App Store** → **Run workflow**.
2. Em uns 15 minutos o build aparece no App Store Connect → **TestFlight**.
3. Instale o app **TestFlight** no iPhone para testar (não expira em 7 dias como o Sideloadly).

## 6. Enviar para revisão da Apple
No App Store Connect, na página do app:
- Cole os textos de `docs/app-store.md` (descrição, palavras-chave etc.).
- **Política de privacidade**: link público para `docs/privacidade.md` (ex.: GitHub Pages).
- **Privacidade do app**: "Dados não coletados".
- **Capturas de tela** do iPhone (6,9"): tire no seu iPhone 17 Pro Max (botão lateral + volume).
- Selecione o build enviado e toque em **Enviar para revisão**. A Apple costuma responder em 1 a 3 dias.
