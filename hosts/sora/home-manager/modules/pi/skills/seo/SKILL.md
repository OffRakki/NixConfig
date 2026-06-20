---
name: seo
description: SEO analysis and technical optimization for web applications, covering JS rendering, SSR, and Google Search Console data interpretation.
---

# SEO — Análise Técnica e Otimização

## Contexto: Produto Cuidados Pela Vida

As páginas de medicamentos participantes (`/medicamentos-participantes/<slug>`) são construídas com Next.js (React + MUI). O conteúdo mais relevante para SEO (indicações, posologia, composição, contraindicações) é carregado via JavaScript assíncrono e **não está presente no HTML inicial (SSR)**.

### Arquitetura Atual

1. **Servidor** renderiza apenas: nome do medicamento, princípio ativo, variações de apresentação, caixa de compra
2. **Cliente** (após hidratação React) faz fetch para API WordPress (`/wp-json/wp/v2/produtos?slug=<medicamento>`) e injeta o conteúdo das abas no DOM
3. Os dados das abas existem em `__NEXT_DATA__` como JSON, mas **não são renderizados como texto visível** no HTML inicial

### Impacto nos Crawlers

| Crawler | Comportamento | Impacto |
|---------|--------------|---------|
| **Googlebot** | Roda Chromium, executa JS | Vê conteúdo parcialmente, mas JS-rendered content é tratado como segunda classe. Indexação leva mais tempo. |
| **Bingbot** | JS limitado | Inconsistente |
| **AI Crawlers (GPTBot, Claude, Common Crawl)** | Apenas HTTP, sem JS | **Não veem o conteúdo das abas** |
| **Social Crawlers (Facebook, Twitter, WhatsApp)** | Sem JS | Previews pobres |

### Ferramentas de Diagnóstico

Use `web_search` para pesquisar documentação do Google Search Console e artigos técnicos.
Use `fetch_content` para extrair conteúdo de URLs de páginas concorrentes, APIs ou ferramentas.
Use pi-chrome (via `browser.py`) para verificar renderização JS real quando o HTML inicial não basta:

```bash
browser.py '[{"action":"navigate","url":"https://cuidadospelavida.com.br/medicamentos-participantes/<slug>"},{"action":"extract"},{"action":"screenshot","path":"/tmp/pi/seo-ssr-check.png"}]'
```

Para inspecionar o HTML estático (SSR) e comparar com o JS-renderizado:

```bash
# Verificar HTML inicial (SSR) — sem execução JS
# Prefer fetch_content in chat, or use a deliberate CLI fetch when raw HTML matters:
nix shell nixpkgs#curl -c curl -L https://cuidadospelavida.com.br/medicamentos-participantes/<slug>

# Verificar HTML completo — com execução JS (via Chromium headless)
nix shell nixpkgs#chromium -c chromium --headless --no-sandbox \
  --dump-dom https://cuidadospelavida.com.br/medicamentos-participantes/<slug>

# Verificar dados disponíveis em __NEXT_DATA__
python3 -c "
import re, json
import urllib.request
html = urllib.request.urlopen('https://cuidadospelavida.com.br/medicamentos-participantes/<slug>').read()
m = re.search(r'<script id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>', html.decode(), re.DOTALL)
if m:
    data = json.loads(m.group(1))
    pp = data.get('props',{}).get('pageProps',{})
    print('pageProps keys:', list(pp.keys()))
    prod = pp.get('product',{})
    print('Product fields:', list(prod.keys()))
    print('Principio_ativo:', prod.get('Principio_ativo',''))
    print('Informações (tab):', str(prod.get('Informacoes',{}).get('Conteudo_informacoes',''))[:200])
    print('Composicao:', str(prod.get('Composicao',''))[:200])
    print('Posologia:', str(prod.get('Posologia',''))[:200])
"

# Acessar conteúdo via API WordPress diretamente
# (fonte de verdade para o conteúdo das abas)
# Prefer fetch_content for readable extraction, or raw JSON via curl:
nix shell nixpkgs#curl -c curl -L "https://conteudodoc.cuidadospelavida.com.br/wp-json/wp/v2/produtos?slug=<slug>"
```

---

## Padrão de Resultados Inconsistentes

Otimizações de superfície (meta tags, títulos, descrições) amplificam o que já está visível no HTML inicial. Se o HTML inicial é fraco, a otimização expõe essa fragilidade.

### Interpretação de Dados do Search Console

| Padrão | Diagnóstico |
|--------|-------------|
| Posição melhorou + impressões subiram | Página já tinha conteúdo semântico suficiente no HTML inicial. Otimização amplificou. |
| Posição piorou + impressões subiram | Google está mostrando a página para mais queries, mas ranqueando abaixo. Concorrentes com SSR mais rico venceram. |
| Posição piorou + impressões estáveis/queda | Página perdeu relevância para seus termos principais. Conteúdo JS-dependente não foi indexado a tempo. |
| Posição estável + impressões estáveis | Google já consolidou o entendimento da página. Otimizações de superfície não mudaram nada. |

### Exemplo Real (Junho 2026)

| Página | Pos Δ | Imp Δ | Diagnóstico |
|--------|-------|-------|-------------|
| Roteas | ↑0.5 | +2.755 (7x) | Melhorou de posição fraca (8.0). Impressions explodiram — página agora ranqueia para mais queries. |
| Betalor | ↑1.9 | +465 | Melhorou significativamente de posição fraca (9.0). |
| Combfix | ↓1.3 | -110 | Caiu de posição forte (6.9). Alta concorrência (tramadol) — Google reavaliou e achou o SSR thin. |
| Clilon | ↓2.0 | +1.930 | Posição caiu dramaticamente. Impressões triplicaram (mais queries) mas ranqueou abaixo. |
| Ansentron | →0 | +310 | Estável. Já tinha a melhor posição e maior volume. |

---

## Solução: Server-Side Rendering do Conteúdo das Abas

### O que implementar

Os dados ACF do WordPress (`acf.composicao`, `acf.posologia`, `acf.informacoes`) já existem — precisam ser **renderizados no HTML inicial** em vez de carregados via API no cliente.

### Alterações no Código

1. **No `getServerSideProps`** da página `[[...slug]].tsx`:
   - Extrair `acf.composicao`, `acf.posologia`, `acf.informacoes` dos dados do produto
   - Passar como props para o componente

2. **No componente React**:
   - Renderizar o conteúdo das abas diretamente no JSX (não via fetch)
   - Manter interatividade das abas (CSS `display: none` / `hidden` para abas inativas)
   - Conteúdo de todas as abas presente no HTML desde o primeiro byte

3. **Remover** a chamada `fetch()` para o conteúdo das abas no cliente

### Benefícios Esperados

- Indexação instantânea para todos os crawlers (incluindo AI crawlers)
- Social previews ricos
- Melhora em Core Web Vitals (uma única renderização no servidor)
- Posição consistente entre páginas — sem efeitos colaterais negativos

### Métricas para Monitorar

Após deploy, monitorar no Search Console por 30 dias:

- Aumento de impressões para páginas que declinaram (Combfix, Clilon, Sabine)
- Recuperação de posição para as mesmas
- Nenhuma página deve piorar (SSR adiciona conteúdo, nunca remove)

---

## Notas Técnicas

- **Googlebot** (2026): usa Chromium moderno, executa JS, mas conteúdo JS-renderizado é depriorizado. Google recomenda explicitamente que conteúdo crítico para SEO esteja no HTML inicial.
- **`__NEXT_DATA__`**: Google pode ou não parsear o JSON dentro deste script tag. Não confiar que será indexado.
- **Fluxo de dados**: WordPress (ACF) → API REST → Next.js → SSR HTML. O pipeline já existe — só falta o último passo.
