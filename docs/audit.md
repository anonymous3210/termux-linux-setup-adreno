# Auditoria e correção do `termux-linux-setup`

## Respostas diretas

1. **O novo instalador não instala o driver Mesa/Vulkan nativo antigo do Termux, mas também não remove uma instalação antiga já presente.** Os pacotes Termux/Bionic `mesa-zink`, `mesa-vulkan-icd-freedreno` e `vulkan-loader-android`, se já instalados, ficam no host para evitar quebrar apps nativos. No Debian/PRoot, o launcher aponta explicitamente para o novo ICD K11 em `/opt/k11-turnip`. Esse isolamento foi validado estaticamente; a GPU real ainda precisa ser testada num aparelho Adreno.
2. **As camadas estão incluídas no plano de instalação:** Debian/PRoot fornece o ambiente glibc; `libvulkan_freedreno.so` é o ICD Vulkan; as bibliotecas Zink incluídas no pacote servem para OpenGL sobre Vulkan. As variáveis de seleção ficam confinadas à sessão PRoot. Isso não é Winlator: o app Winlator não é instalado.
3. **O script foi corrigido e passou testes estáticos e simulados**, descritos abaixo.
4. **O pacote Android Emulator foi instalado, mas não validou o Android/Termux.** O AVD ARM64 foi recusado porque o host x86_64 não suporta essa imagem; o AVD x86_64 respondeu ao ADB com Android 15, EGL `emulation` e Vulkan `ranchu`, mas não chegou a informar `sys.boot_completed=1` e foi encerrado. O teste gráfico foi feito separadamente por Xvfb/llvmpipe.

## O que foi mudado

A nova versão usa `pkg` para o host Termux e instala Debian via `proot-distro`; os pacotes Debian são instalados com `apt-get` apenas dentro do Debian glibc. O menu oferece XFCE4, LXQt, MATE e KDE Plasma. A opção escolhida muda apenas os pacotes e o comando de sessão; `install_k11_driver` é chamado sem condição para todas as opções. Ela baixa a release `winlator_v25.1_r2`, valida o SHA-256 esperado, valida que o driver é ELF AArch64 com dependências glibc, extrai somente os quatro arquivos previstos e gera um ICD com caminho isolado. O asset `.wcp` foi inspecionado e extraído sem executar código.

Os launchers usam Termux:X11 no display `:1` com `--shared-tmp`. A lógica de instalar os pacotes Mesa/Vulkan antigos foi removida; não há remoção automática de pacotes Termux/Bionic previamente instalados, pois não são dependências do ICD glibc no Debian e podem atender apps nativos. Também foram removidos o `pkill -9` global, o encerramento de D-Bus alheio, as variáveis MESA que fingiam capacidades OpenGL e a instalação Hangover/Wine. Há comandos separados para verificar Vulkan (`~/verify-turnip.sh`) e OpenGL/Zink (`~/verify-glx.sh`).

## Testes executados

- `bash -n` passou para o instalador e para os quatro launchers gerados.
- Selftest usando o `.wcp` real passou: SHA-256 `daa18f4d1dfcc79bb6cf71580f37a3c7b0bbb054895bff1007b6dd45b82a79f4`, ELF AArch64, dependência glibc e manifesto ICD em `/opt/k11-turnip/lib/libvulkan_freedreno.so`.
- Artefato WCP inválido foi recusado pelo SHA-256 antes de qualquer etapa de instalação.
- Falha simulada de `pkg update` foi registrada e propagada; nenhuma etapa posterior correu.
- Todas as quatro opções de desktop foram simuladas: cada uma selecionou seu pacote/comando de sessão e, em todas, o log confirmou a etapa obrigatória de instalação K11. A opção 1 foi usada para a simulação XFCE/Xvfb descrita abaixo.
- Simulação GUI passou: foi executado o launcher gerado pelo script, usando stubs apenas para Termux:X11/PRoot e um Xvfb com software rendering. A sessão `xfce4-session`/`xfwm4` iniciou, uma janela `xfce4-terminal` apareceu, o comando escreveu o marcador esperado e `glxinfo` identificou `llvmpipe (LLVM 20.1.2, 256 bits)`. A captura está anexada abaixo.
- Não foi executado `vulkaninfo` com o K11 em GPU real nem `glxinfo` no Termux:X11 de Android. A simulação valida a sessão gráfica e o terminal sob renderização CPU, mas não prova compatibilidade do ICD com KGSL/Adreno.

## Limite importante do driver solicitado

A página consultada aponta a versão `25.1.0 Revision 2`, publicada em 17/02/2025. O repositório está arquivado. A `.so` é ARM64 e depende de glibc (`libc.so.6`, `ld-linux-aarch64.so.1`), portanto não é uma substituição direta para o processo nativo Bionic do Termux. O `.wcp` inclui caminhos originalmente destinados ao container do Winlator; o script reescreve o caminho do ICD para o Debian/PRoot. Assim, o código está adaptado para **usar exatamente esse driver**, mas não posso afirmar que esse seja o Turnip mais atual em 2026 nem certificar compatibilidade de hardware sem um Snapdragon/Adreno real.

O Android Emulator instalado é a versão 37.2.12.0, com `adb` 37.0.1. A imagem ARM64 falhou por incompatibilidade com o host x86_64. A imagem x86_64 respondeu com `ro.hardware.egl=emulation` e `ro.hardware.vulkan=ranchu`, não Adreno, e não completou o boot durante a tentativa. O AVD foi encerrado. A simulação Xvfb foi usada para testar o desktop sem depender do AVD. As fontes oficiais do Android descrevem KVM como aceleração Linux e TCG sem aceleração como muito lento; a documentação do próprio Termux:X11 requer `--shared-tmp` para PRoot.

## Artefatos

- Script corrigido na raiz do repositório: [`termux-linux-setup.sh`](../termux-linux-setup.sh)
- Captura do XFCE com renderização por software: [`termux-linux-software-simulation.png`](termux-linux-software-simulation.png)

## Referências

[1]: https://github.com/orailnoor/termux-linux-setup/blob/main/termux-linux-setup.sh "Script original"
[2]: https://github.com/K11MCH1/WinlatorTurnipDrivers/releases/tag/winlator_v25.1_r2 "Release K11MCH1 Turnip v25.1.0 Revision 2"
[3]: https://docs.mesa3d.org/drivers/freedreno.html "Documentação Mesa Freedreno e Turnip"
[4]: https://github.com/termux/proot-distro "Documentação oficial PRoot-Distro"
[5]: https://github.com/termux/termux-x11 "Documentação oficial Termux:X11"
[6]: https://developer.android.com/studio/run/emulator-acceleration "Aceleração do Android Emulator"
[7]: https://developer.android.com/studio/run/emulator-commandline "Opções de linha de comando do Android Emulator"
[8]: https://github.com/LinuxDroidMaster/Termux-Desktops/blob/main/Documentation/HardwareAcceleration.md "Guia comunitário de aceleração gráfica no Termux/PRoot"
