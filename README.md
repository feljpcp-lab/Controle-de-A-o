# FELJ — Controle de Aço

Aplicação web para controle de barras, rastreabilidade de fornecedor/NF/certificado, listas de corte, apontamento da serra, sobras e ajustes de inventário.

## Publicação
- Aplicação estática em `index.html`, pronta para GitHub Pages.
- Backend: Supabase FELJ existente (`jklgvpmgvkooghfhnirq`).
- URL do Supabase: `https://jklgvpmgvkooghfhnirq.supabase.co`.
- Usa somente a chave publicável no navegador; nunca coloque `service_role` ou chave secreta no frontend.

## Regras operacionais implementadas
- Criar lista/planejar peças não baixa estoque.
- O apontamento confirmado da serra baixa 1 barra por operação, de forma transacional.
- Perda de serra: 3 mm por corte para diâmetro menor que 250 mm; 4 mm para diâmetro igual ou maior que 250 mm.
- O sistema calcula consumo e sobra; sobras reutilizáveis de pelo menos 100 mm entram no cadastro de remanescentes.
- Ajuste físico registra sistema, contagem, diferença, justificativa e movimento de estoque.
- Todas as tabelas novas usam prefixo `aco_`; tabelas existentes não são modificadas.

## Perfis de acesso
Criar usuários em Supabase Auth e definir o papel em **app_metadata.role** (não em user_metadata):
- `admin`: acesso completo;
- `pcp`: estoque, entrada, listas, apontamento e ajuste;
- `almoxarifado`: estoque, entrada e ajuste;
- `serra`: somente painel e apontamento da serra.

O papel precisa ser definido por mecanismo administrativo confiável no Supabase; não pode ser definido pelo próprio usuário. Após mudar app_metadata, renovar a sessão do usuário.

## Limitações desta primeira entrega
- A lista de corte é cadastrada manualmente; leitura automática do PDF ainda não está implementada.
- O campo de certificado aceita URL/caminho de referência. Upload direto de arquivo requer criar bucket privado e políticas de Storage.
- A autenticação usa e-mail/senha do Supabase Auth. Para login por nome de usuário, será necessária uma camada de autenticação específica.
- Um apontamento corresponde a uma barra inteira; para um corte que use mais de uma barra, registrar cada barra como apontamento separado. Isso mantém o saldo consistente e permite rastrear cada sobra.

## Banco de dados
Os objetos `aco_lotes`, `aco_listas_corte`, `aco_itens_lista_corte`, `aco_apontamentos_serra`, `aco_remanescentes`, `aco_ajustes_inventario`, `aco_movimentacoes` e as funções `aco_*` são exclusivos do controle de aço. A política de Row Level Security usa `auth.jwt()->'app_metadata'->>'role'`.

## Ativação do endereço público
O workflow `.github/workflows/deploy.yml` já está versionado. Para ativar a hospedagem na primeira vez, abra **Settings → Pages** no repositório e selecione **Build and deployment → Source: GitHub Actions**. Depois, confira a aba **Actions** até o workflow ficar verde. Não considero o site publicado até essa execução ser confirmada.

## Preparar os usuários
No Supabase Dashboard, em **Authentication → Users**, crie os usuários autorizados. Para cada usuário, atribua no campo `app_metadata` o papel `role` com um dos valores descritos acima. A equipe da serra recebe `serra`, e a interface restringe esse perfil à tela de apontamento. Não atribua permissões usando `user_metadata`, pois esse campo pode ser editado pelo usuário.
