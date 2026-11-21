# Maintainer: Gehrman-Sparrow-ark
pkgname=lyrics-widget
pkgver=1.0.0
pkgrel=2
pkgdesc='Floating synced-lyrics widget for Quickshell (MPRIS, LRCLIB, Kugou, NetEase)'
arch=('any')
url='https://github.com/YOURNAME/lyrics-widget'
license=('MIT')
depends=('python' 'quickshell')
optdepends=('noto-fonts-cjk: show Chinese, Japanese and Korean lyrics correctly')
source=('lyrsearch' 'lyrsave' 'shell.qml' 'lyrics-widget-setup' 'LICENSE')
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')

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
