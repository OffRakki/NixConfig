# Political research sources and access

This is a routing catalogue, not a reliability score or claim that every listed
service is currently reachable. Start with the curated set; use extended sources
when they offer relevant original reporting or expose a claim worth checking.
Verify the current domain, date, authorship, and methodology during the actual task.
Do not promote an outlet to 'verified' because it appears here. No source is
mandatory for every question, and this catalogue is not an allowlist.

## 1. Curated reporting set

| Source / entry point | Best use | How to access / limit |
|---|---|---|
| Reuters — https://www.reuters.com/world/americas/ | Major political/economic events and independent international reporting. | Search `site:reuters.com Brazil <topic>` and fetch the exact article. Brazilian coverage is selective, often in English. Accuracy/corrections policy: https://reutersagency.com/about/standards-values/ |
| g1 — https://g1.globo.com/politica/ | Daily developments, elections, regional reporting. | Search `site:g1.globo.com <claim/event/place>`, then open the article and linked original record. Separate reporting from commentary. |
| BBC News Brasil — https://www.bbc.com/portuguese | Explanations, international context, background. | Search by subject and author/date; inspect the full piece. Not a complete daily legislative record. |
| JOTA — https://www.jota.info/ | Courts, legislative detail, regulatory affairs. | Search case number, bill number, or legal topic. Separate reporting from contributed opinion. Some coverage is paid. |
| Nexo — https://www.nexojornal.com.br/ | Concepts, historical context, policy explanations. | Follow data and research links; distinguish explanation, interview, and opinion. Some coverage is paid. |
| Agência Pública — https://apublica.org/ | Investigations into public/private power and policy impacts. | Follow documents, underlying data, methodology, and responses. Investigative agenda, not general daily coverage. |

Do not count g1, O Globo, and Valor as three independent editorial ownership groups;
likewise, do not assume Folha/UOL or other related brands have independent sources.
Ownership is a dependence warning, not proof that reporting was copied. Inspect
actual bylines, agency credits, source chains, and original contributions.

## 2. Legislature, legal acts, courts, and elections

### Câmara dos Deputados

- Portal: https://www.camara.leg.br/ ; institutional news:
  https://www.camara.leg.br/noticias/
- Open data and interactive API docs: https://dadosabertos.camara.leg.br/
  and https://dadosabertos.camara.leg.br/swagger/api.html
- API base: `https://dadosabertos.camara.leg.br/api/v2/`
- Search a proposition by type, number, and year. Inspect its detail record,
  íntegra, amendments/substitutivos, tramitação, and related votes. Establish which
  version and legislative stage the news describes; inspect nominal votes when
  available. Follow pagination and documented links instead of assuming completeness.
- Concrete discovery query:
  `https://dadosabertos.camara.leg.br/api/v2/proposicoes?siglaTipo=PL&numero=2630&ano=2020`
  This is a lookup example, not a statement about the proposal's current status.

### Senado Federal

- Portal: https://www.senado.leg.br/ ; news: https://www12.senado.leg.br/noticias/
- Data catalogue: https://www12.senado.leg.br/dados-abertos/legislativo
- API base: `https://legis.senado.leg.br/dadosabertos/`
- API docs: https://legis.senado.leg.br/dadosabertos/api-docs/swagger-ui/index.html
- Locate the matéria/processo, authored text, relatoria, amendments, movement,
  session, voting result, and individual votes. Check docs for current JSON/XML
  negotiation, parameters, and resource names. Câmara and Senado institutional
  stories guide discovery but are not independent political analysis.

### Legislation and Diário Oficial da União

- Legal texts: https://www.planalto.gov.br/ccivil_03/
- Official publication: https://www.in.gov.br/
- Search the act's type, number, year, issuer, and publication date. Inspect annexes,
  later amendments, veto messages, revocation, transitional rules, and effective
  dates. For historical questions, reconstruct the text in force at that date,
  not merely today's consolidated text. Publication does not always mean immediate
  effectiveness. State/municipal acts require the respective official gazette.

### STF and other courts

- STF portal: https://portal.stf.jus.br/
- Search by case class/number, parties, date, or decision. Inspect public andamento,
  signed decision/inteiro teor, operative order, votes, and later procedural changes.
  Case number and date are preferable to headlines. For other courts, use their
  own official records; an STF search cannot settle a state-court case.
- Press releases are secondary descriptions of court action. A case filing is
  primary evidence of an allegation, not proof of the alleged conduct. Respect
  sealed proceedings and report limits of public access precisely.

### TSE / electoral records

- Portal: https://www.tse.jus.br/
- DivulgaCandContas entry:
  https://www.tse.jus.br/administracao/painel/divulgacao-de-candidaturas-e-contas-eleitorais
- Open-data catalogue: https://dadosabertos.tse.jus.br/
- Fato ou Boato: https://www.justicaeleitoral.jus.br/desinformacao/
- Filter by election/year, office, state/municipality, candidate, and account status.
  Inspect receipts, expenses, donors, declared assets, filing versions, and relevant
  judgments. Check each dataset dictionary and update date. Submitted declarations
  are not audited market valuations; missing records are not proof of concealment.
- For results and polling registration, navigate from the TSE portal to the
  relevant election/results service or PesqEle. Do not infer fraud from a screenshot,
  partial count, isolated discrepancy, or absence of a record without investigation.

## 3. Statistical and fiscal evidence

### IBGE / SIDRA

- https://www.ibge.gov.br/ ; https://sidra.ibge.gov.br/
- Public API: https://apisidra.ibge.gov.br/
- Search the relevant survey/indicator and table. Select variable, classification,
  geography, period, and unit in SIDRA; use its 'Parâmetros para a API' or export
  facilities to obtain the actual query. Do not guess table or variable codes.
- Retrieve the methodology and notes alongside the values. For work/income, check
  PNAD Contínua population definitions and sampling; for inflation, distinguish
  IPCA/INPC and monthly/year-to-date/12-month rates; for GDP, distinguish nominal
  levels and real volume growth. Check revisions and seasonal adjustment.

### Banco Central / SGS

- https://www.bcb.gov.br/ ; https://dadosabertos.bcb.gov.br/
- Find the dataset by indicator name, then verify its SGS code, unit, frequency,
  source, metadata, and documented API resource before extraction.
- Documented BCData shape:
  `https://api.bcb.gov.br/dados/serie/bcdata.sgs.<code>/dados?formato=json&dataInicial=DD/MM/YYYY&dataFinal=DD/MM/YYYY`
- Public example (historical daily Selic series 11, percent per day):
  https://api.bcb.gov.br/dados/serie/bcdata.sgs.11/dados?formato=json&dataInicial=01/01/2024&dataFinal=31/01/2024
- Do not confuse daily effective Selic with annual target Selic. Consult current
  endpoint limits; the catalogue documents mandatory filtering/volume restrictions
  for daily JSON/CSV and a maximum ten-year date interval. Chunk large histories.
- Dataset documentation:
  https://dadosabertos.bcb.gov.br/dataset/11-taxa-de-juros---selic

### Tesouro Transparente / Siconfi

- https://www.tesourotransparente.gov.br/
- Siconfi catalogue: https://www.tesourotransparente.gov.br/consultas/consultas-siconfi
- API guide:
  https://www.tesourotransparente.gov.br/consultas/consultas-siconfi/siconfi-api-de-dados-abertos
- Choose the correct debt/fiscal report and reference period. For states and
  municipalities, inspect RREO, RGF, Finbra, or MSC as appropriate; check reporting
  entity, consolidation, account concepts, amendments, and missing submissions.
  Follow the current API documentation for endpoints, filters, and pagination.
- Distinguish central-government results from consolidated public-sector results,
  primary from nominal balance, and gross from net debt. Identify cash/accrual
  basis, intergovernmental transfers, and restated series before comparing.

### Portal da Transparência

- https://portaldatransparencia.gov.br/
- Navigate to the relevant expenditure, transfer, agreement, contract, benefit, or
  entity/person consultation and apply explicit year/entity/location filters.
  Download public data or use the API only under its current documented access rules.
  If a key is required and unavailable, use public UI/downloads; never seek secrets.
- Federal scope is not 'all Brazilian spending'. Trace payment stage, beneficiary,
  time period, and transfer chain; check counterpart state/municipal transparency
  portals where necessary. A supplier being paid does not by itself establish fraud.

### IPEA

- https://www.ipea.gov.br/ ; https://www.ipeadata.gov.br/
- Useful for policy studies, historical series, and socioeconomic research. Inspect
  study authors, publication date, method, underlying data origin, and limitations.
  A research estimate is not automatically an observed official count; institute
  affiliation is not a guarantee of a causal conclusion.

## 4. Fact-checking — inspect the evidence, not only the label

| Source | Entry point | Access and scope |
|---|---|---|
| Aos Fatos | https://www.aosfatos.org/ | Search exact claim/person/date; inspect sources, full reasoning, corrections, and scope. Method: https://www.aosfatos.org/webstories/como-o-aos-fatos-faz-uma-checagem/ |
| AFP Checamos | https://checamos.afp.com/ | Search claim, image description, location, or quotation; inspect provenance and technical verification. Method: https://checamos.afp.com/Manual-de-estilo-de-verificacao-digital-da-AFP |
| Lupa | https://www.agencialupa.org/ | Current working entry; verify redirects and identity if it moves. `lupa.news` and `lupa.uol.com.br` appeared in earlier lists; do not assume an old bookmark is current. |
| Projeto Comprova | https://projetocomprova.com.br/ | Collaborative verification; identify originating investigation and evidence. Participating outlets republishing it do not become independent corroboration. |
| Estadão Verifica | https://www.estadao.com.br/estadao-verifica/ | Viral claims and political misinformation; open full check and linked records. |
| Fato ou Fake | https://g1.globo.com/fato-ou-fake/ | Viral claims; inspect exact version and date of the checked allegation. |
| UOL Confere | https://noticias.uol.com.br/confere/ | Search by claim; inspect evidence and current activity rather than assuming coverage. |
| Boatos.org | https://www.boatos.org/ | Viral messages and contextual debunking; trace original evidence. |
| E-farsas | https://www.e-farsas.com/ | Hoaxes and historical viral claims; verify current activity and the original material. |

A check about one version of a claim may not resolve a later or narrower version.
An agency's institutional method is useful context, not an objective certificate.
For institution-related claims, combine institutional documentation with independent
technical evidence where needed; do not let the institution adjudicate itself alone.

## 5. Extended discovery catalogue from the earlier discussion

These are optional leads, not an endorsement, equal-reliability basket, or required
left/right pairing. Search `site:<domain> <exact claim or document identifier>`, open
the relevant publication, classify reporting versus opinion/advocacy, and trace the
original evidence. For all entries, check current activity and ownership when
material. Editorial labels below describe intended use, not fixed objective scores.

### Additional general, economic, and international reporting

| Source | Entry point |
|---|---|
| Agência Brasil / EBC (public agency; distinguish reporting from government communication) | https://agenciabrasil.ebc.com.br/ |
| UOL Notícias | https://noticias.uol.com.br/ |
| Folha de S.Paulo | https://www.folha.uol.com.br/ |
| Estadão | https://www.estadao.com.br/ |
| O Globo | https://oglobo.globo.com/ |
| Valor Econômico | https://valor.globo.com/ |
| CNN Brasil | https://www.cnnbrasil.com.br/ |
| Associated Press | https://apnews.com/ |
| DW Brasil | https://www.dw.com/pt-br/ |
| Poder360 | https://www.poder360.com.br/ |
| Metrópoles | https://www.metropoles.com/ |
| SBT News | https://sbtnews.sbt.com.br/ |
| Terra | https://www.terra.com.br/ |
| InfoMoney | https://www.infomoney.com.br/ |
| Congresso em Foco | https://www.congressoemfoco.com.br/ |
| Meio (verify current branding/domain) | https://www.canalmeio.com.br/ |
| Piauí (verify redirects from former Folha hosting) | https://piaui.folha.uol.com.br/ |

### Editorial perspectives, advocacy, and analysis

Consult when relevant to original reporting, arguments, political communication,
or a claim being investigated. Do not treat an opinion essay or documentary as
verified daily news. Recognizing a publication's advocacy does not establish that
a particular factual claim is false; inspect the evidence.

| Source | Entry point |
|---|---|
| Gazeta do Povo | https://www.gazetadopovo.com.br/ |
| Revista Oeste | https://revistaoeste.com/ |
| Jovem Pan | https://jovempan.com.br/ |
| O Antagonista | https://oantagonista.com.br/ |
| Crusoé | https://crusoe.com.br/ |
| Diário do Poder | https://diariodopoder.com.br/ |
| Conexão Política | https://www.conexaopolitica.com.br/ |
| Brasil Paralelo (documentaries/analysis; inspect original references) | https://www.brasilparalelo.com.br/ |
| Terra Brasil Notícias (not the Terra portal) | https://terrabrasilnoticias.com/ |
| Brasil de Fato | https://www.brasildefato.com.br/ |
| Brasil 247 | https://www.brasil247.com/ |
| CartaCapital | https://www.cartacapital.com.br/ |
| Diário do Centro do Mundo | https://www.diariodocentrodomundo.com.br/ |
| Opera Mundi | https://operamundi.uol.com.br/ |
| Revista Fórum | https://revistaforum.com.br/ |
| Esquerda Diário | https://www.esquerdadiario.com.br/ |
| Outras Palavras | https://outraspalavras.net/ |
| A Terra é Redonda (primarily essays/opinion) | https://aterraeredonda.com.br/ |
| Rede Brasil Atual | https://www.redebrasilatual.com.br/ |
| Jornal GGN | https://jornalggn.com.br/ |
| Carta Maior (confirm current publishing activity) | https://www.cartamaior.com.br/ |
| Mídia NINJA (engaged coverage/advocacy) | https://midianinja.org/ |

### Investigative, regional, environmental, and academic coverage

| Source | Entry point |
|---|---|
| Intercept Brasil (independent Brazilian site; old `theintercept.com/brasil` appeared in earlier lists) | https://www.intercept.com.br/ |
| Plural | https://www.plural.jor.br/ |
| Sul21 | https://sul21.com.br/ |
| Amazônia Real | https://amazoniareal.com.br/ |
| InfoAmazonia | https://infoamazonia.org/ |
| ((o))eco | https://oeco.org.br/ |
| Jornal da USP | https://jornal.usp.br/ |

### Historical or unresolved entries

- **Truco:** historical Agência Pública fact-checking project; start from
  https://apublica.org/ and locate the dated archive. Not presumed an active service.
- **Revista Timeline:** the earlier catalogue did not establish a canonical domain,
  responsible team, or current activity. No URL is invented here. Verify identity,
  publication history, and editorial responsibility before using any candidate.
- **Reuters Institute Digital News Report:** https://reutersinstitute.politics.ox.ac.uk/digital-news-report
  Locate the actual published edition and Brazil methodology. Surveyed trust is
  audience perception, not an objective newsroom reliability ranking. Never cite
  an edition solely because a previous generated answer asserted it exists.

## 6. Choosing a route, not collecting logos

- **'Did a politician vote for X?'** Câmara/Senado nominal record, exact vote/text,
  procedural context, then independent reporting if the political meaning is disputed.
- **'Did the STF ban X?'** Identified case and operative order, date and subsequent
  status, then specialized legal reporting; not a cropped social-media quotation.
- **'Did unemployment/inflation/debt improve?'** IBGE/BCB/Tesouro series and metadata,
  matched definitions and period, transparent comparison, then causal research if
  the question attributes the change to a policy or administration.
- **'Was public money diverted?'** Original expenditure/contract/audit/proceeding,
  appropriate jurisdiction, independent investigation, procedural status, and the
  subject's material response. Spending or an accusation alone is not proof of theft.
- **'Is this viral clip real?'** Original recording, context/date/location, independent
  provenance, and relevant fact-check. An authentic clip can still carry a false caption.
- **'What is the political intention?'** Verified words/actions/timing/incentives,
  documented relationships and competing explanations; deliver a supported strategic
  interpretation, not a purported readout of private thoughts.
