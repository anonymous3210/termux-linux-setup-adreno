# Termux Linux Setup — Adreno / Termux:X11

Versão corrigida do instalador para escolher XFCE, LXQt, MATE ou KDE Plasma dentro de Debian/PRoot no Termux e configurar o driver K11 Turnip em um ambiente glibc isolado.

> **Estado de validação:** sintaxe, validação de artefato e fluxo de erro passaram testes simulados. O launcher XFCE e um terminal foram abertos em Xvfb com renderização CPU (`llvmpipe`). Ainda não houve execução em um telefone Snapdragon/Adreno; portanto, compatibilidade com KGSL e inicialização real do ICD Turnip não estão certificadas.

## O que instala

- Dependências de host pelo `pkg` do Termux, incluindo `proot-distro` e `termux-x11-nightly`.
- Debian com glibc via PRoot; o desktop escolhido e seu terminal correspondente.
- Driver K11 Turnip `v25.1.0-R2` em `/opt/k11-turnip`, com SHA-256 fixado e manifesto ICD ajustado.
- Launchers e verificadores para iniciar o desktop escolhido, resumir Vulkan e conferir OpenGL/Zink.

O app Android **Termux:X11** precisa estar instalado separadamente e aberto para visualizar a sessão. O app Winlator não é instalado nem iniciado; o pacote `.wcp` é usado apenas como contêiner dos arquivos do driver.

O menu oferece `1) XFCE4`, `2) LXQt`, `3) MATE` e `4) KDE Plasma` (padrão: XFCE4). **A instalação do K11 é obrigatória e independente da opção escolhida**: a opção seleciona apenas o conjunto de pacotes e o comando da sessão gráfica.

## Requisitos e cautelas

- Termux oficial em Android **AArch64** e uma GPU Adreno detectável por `getprop`.
- Espaço livre para o rootfs Debian e seus pacotes; o script atualiza índices de pacotes e instala software.
- A release K11 selecionada é de 2025 e o repositório de drivers está arquivado. “Turnip 6xx” no título da release não garante suporte a todo Adreno 6xx, kernel ou firmware. Verifique a compatibilidade do seu aparelho antes de instalar.
- O driver foi compilado para glibc; não deve ser carregado diretamente em processos nativos Bionic do Termux. O PRoot fornece o userland glibc, mas não traduz nem garante compatibilidade com o driver/kernel Android.
- O script não instala os antigos pacotes Termux/Bionic `mesa-zink`, `mesa-vulkan-icd-freedreno` nem `vulkan-loader-android`; também **não os desinstala se já estiverem presentes**. Eles são separados do ICD glibc selecionado no Debian/PRoot e são preservados para não afetar apps nativos do Termux.
- A validação `llvmpipe` é apenas do caminho gráfico por software; não valida o Turnip nem o acesso real a KGSL.

## Instalação no Termux

Baixe este repositório no Termux, confirme que está no Termux oficial e execute:

```bash
bash termux-linux-setup.sh
```

O script verifica arquitetura/GPU, apresenta o menu de desktop e grava um log em `~/termux-linux-setup.log`. Em execução não interativa, usa XFCE4 por padrão; também é possível definir `DESKTOP_CHOICE=1`, `2`, `3` ou `4`. **Em todos os casos, a etapa de instalação do K11 roda obrigatoriamente.** O script não apaga um rootfs Debian já existente. O driver é isolado em `/opt/k11-turnip` dentro do Debian.

Após a instalação:

```bash
~/start-linux.sh
```

Abra o app Android Termux:X11 para ver o desktop selecionado. Para diagnóstico:

```bash
~/verify-turnip.sh
~/verify-glx.sh
```

Os comandos de verificação precisam ser executados com o Termux:X11 aberto quando consultam OpenGL.

## Testes deste repositório

Veja [`docs/audit.md`](docs/audit.md) para os testes executados, detalhes do pacote e fontes. A captura [`docs/termux-linux-software-simulation.png`](docs/termux-linux-software-simulation.png) mostra XFCE e a saída do terminal sob `llvmpipe`.

## Origem

Baseado no script público [orailnoor/termux-linux-setup](https://github.com/orailnoor/termux-linux-setup). A versão nesta branch é uma adaptação de teste, não uma confirmação de compatibilidade universal nem uma release oficial do projeto original.
