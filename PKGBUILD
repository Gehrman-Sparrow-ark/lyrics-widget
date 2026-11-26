# Maintainer: Gehrman-Sparrow-ark
pkgname=lyrics-widget
pkgver=1.3.3
pkgrel=1
pkgdesc='Floating synced-lyrics widget for Quickshell (MPRIS, LRCLIB, Kugou, NetEase)'
arch=('any')
url='https://github.com/Gehrman-Sparrow-ark/lyrics-widget'
license=('MIT')
depends=('python' 'quickshell')
optdepends=('noto-fonts-cjk: show Chinese, Japanese and Korean lyrics correctly')
install=lyrics-widget.install
options=('!debug')
source=('lyrsearch' 'lyrsave' 'shell.qml' 'lyrics-widget-setup' 'LICENSE')
sha256sums=('c067bc38fe725c4763a638f55aed459f57497b35d2a62ea65ada775880e81afd'
            '7ab9e71fa2d2b1f4a14af06e3d18565948e2de82a6ae78760c52e1dc5a1c7654'
            'a9e12eac02c1c2ca068d8939d870436f1387980dc8a63ac615272141365f94ca'
            '8726ca073c43b09efc40bf32a8541e1521320d41c91e52168bd1aa557507537b'
            'bac14a0ca1d1815d23855ebdbd75ad45d10501d72202fd8df4da0ea3f1507cd9')

prepare() {
    sed -i 's|home + "/.local/bin/lyrsearch"|"/usr/bin/lyrsearch"|; s|home + "/.local/bin/lyrsave"|"/usr/bin/lyrsave"|' shell.qml
    grep -q '"/usr/bin/lyrsearch"' shell.qml
    grep -q '"/usr/bin/lyrsave"' shell.qml
}

package() {
    install -Dm755 lyrsearch "$pkgdir/usr/bin/lyrsearch"
    install -Dm755 lyrsave "$pkgdir/usr/bin/lyrsave"
    install -Dm755 lyrics-widget-setup "$pkgdir/usr/bin/lyrics-widget-setup"
    install -Dm644 shell.qml "$pkgdir/usr/share/lyrics-widget/shell.qml"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
