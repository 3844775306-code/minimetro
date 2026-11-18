# Noto Sans SC

`NotoSansSC-Regular.otf` is the Noto Sans SC Regular font by Google/Adobe,
used only so the Web build can render Chinese without relying on system fonts.
It is distributed under the SIL Open Font License 1.1:
https://openfontlicense.org/open-font-license-official-text/

The desktop/mobile builds continue to use the operating system's CJK font first;
the bundled font is loaded when `OS.has_feature("web")` is true.
