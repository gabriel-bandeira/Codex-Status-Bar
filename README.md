# Codex Status Bar

Aplicativo nativo para macOS que mostra os limites restantes do Codex diretamente na barra de menus.

O app exibe dois percentuais restantes lado a lado:

```text
5h 25% | Sem 48%
```

O primeiro valor representa o limite restante da janela de 5 horas. O segundo representa o limite semanal restante.

## Como Funciona

O app nao usa API HTTP externa nesta versao. A cada 30 segundos, ele tenta ler os limites diretamente do Codex usando:

```text
codex app-server
```

Internamente, o app chama o metodo JSON-RPC:

```text
account/rateLimits/read
```

Se o executavel `codex` nao estiver disponivel ou a chamada direta falhar, o app usa fallback lendo snapshots locais em:

```text
~/.codex/sessions
```

Nesse fallback, ele:

1. Procura arquivos recentes `rollout-*.jsonl`.
2. Le os snapshots mais novos.
3. Busca o objeto `rate_limits`.
4. Mapeia `primary` como limite de 5 horas.
5. Mapeia `secondary` como limite semanal.
6. Converte `used_percent` em percentual restante usando `100 - used_percent`.
7. Atualiza os percentuais na barra de menus.

No menu suspenso, o app mostra:

- percentual restante nas proximas 5 horas;
- tempo restante ate renovar a janela de 5 horas;
- horario local da renovacao de 5 horas;
- percentual restante na semana;
- tempo restante ate renovar a janela semanal;
- horario local da renovacao semanal;
- data e hora local exata da informacao exibida;
- idade do snapshot, quando o app estiver usando fallback local;
- opcao `Abrir ao iniciar`;
- opcao `Fechar App`.

Importante: quando a leitura vem de `codex app-server`, ela representa a informacao consultada naquele momento. Quando vem dos arquivos `rollout-*.jsonl`, ela representa o horario do snapshot local mostrado no menu como `Atualizado em ...`.

## Consome Tokens?

O app nao envia prompts, nao inicia uma conversa e nao pede geracao de texto ao modelo.

A leitura direta usa `account/rateLimits/read` no `codex app-server`, que consulta metadados de limite da conta. O fallback apenas le arquivos locais `rollout-*.jsonl`. Portanto, a expectativa e que o app nao consuma tokens do Codex; ele apenas consulta ou reaproveita informacoes de limite ja registradas.

## Instalar Build Local

Existe uma build local pronta em:

```text
dist/Codex-Status-Bar-local-arm64.zip
```

Essa build e para Macs Apple Silicon.

Para usar:

1. Baixe `dist/Codex-Status-Bar-local-arm64.zip`.
2. Extraia o arquivo.
3. Mova `Codex Status Bar.app` para `/Applications`.
4. Abra o app com botao direito > `Open` na primeira execucao.
5. Se o macOS bloquear, va em `System Settings > Privacy & Security` e clique em `Open Anyway`.
6. Depois de abrir, use o menu da barra de menus e ative `Abrir ao iniciar`.

## Abrir Automaticamente ao Ligar o Mac

O menu do app possui a opcao:

```text
Abrir ao iniciar
```

Ao ativar essa opcao, o app usa `SMAppService.mainApp` para registrar o proprio aplicativo como item de inicio do macOS. Ele passa a aparecer em:

```text
System Settings > General > Login Items
```

Voce pode desativar pelo proprio menu do app ou pelos Ajustes do Sistema.

## Sobre Assinatura e Gatekeeper

Esta build nao e notarizada pela Apple e nao usa Developer ID, porque isso exige uma conta paga do Apple Developer Program.

Ela e uma build local assinada ad-hoc. Isso significa:

- funciona bem para uso pessoal/hobbista;
- o macOS pode bloquear a primeira abertura;
- outro Mac precisa confiar manualmente no app;
- nao ha revisao da App Store;
- nao ha notarizacao da Apple.

Sem Developer ID, o fluxo esperado e aceitar manualmente o app na primeira execucao usando `Open Anyway` em `Privacy & Security`.

## Build Local Pelo Xcode

Para gerar uma build local pelo Xcode:

1. Abra o projeto no Xcode.
2. Selecione o target `Codex Status Bar`.
3. Confirme que `Application is agent (UIElement)` / `LSUIElement` esta como `YES`.
4. Para uso local chamando `codex app-server` e lendo `~/.codex/sessions`, desative `App Sandbox` ou implemente permissao por pasta com security-scoped bookmark.
5. Use `Product > Archive` ou rode o app diretamente pelo Xcode.

Tambem e possivel gerar por linha de comando com assinatura ad-hoc:

```sh
xcodebuild \
  -project "Codex Status Bar.xcodeproj" \
  -scheme "Codex Status Bar" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  INFOPLIST_KEY_LSUIElement=YES \
  ENABLE_APP_SANDBOX=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  build
```

## Limitacoes Atuais

- A build pronta e apenas arm64.
- A leitura direta depende do executavel `codex` estar instalado em um caminho que o app consiga encontrar.
- Com App Sandbox ativo, o app pode nao conseguir executar `codex app-server` nem ler `~/.codex/sessions`.
- Ainda nao ha tela para escolher a pasta `.codex` e salvar permissao persistente.

## Proximos Passos Possiveis

- Adicionar seletor de pasta `.codex` com security-scoped bookmark.
- Criar build universal `arm64 + x86_64`.
- Adicionar configuracao manual do caminho do executavel `codex`.
- Criar GitHub Release com o zip anexado.
