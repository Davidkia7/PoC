# Oggy Inu Price Manipulation PoC (Test JS)

Proof of Concept untuk menunjukkan manipulasi harga kecil pada kontrak "Oggy Inu" menggunakan tes JavaScript di Hardhat Network.

## Deskripsi
PoC ini menguji kemampuan pemilik untuk:
- Menurunkan `swapTokensAtAmount` ke nilai kecil.
- Melakukan transfer kecil untuk memicu `swapAndLiquify`.
- Mengalihkan BNB pajak ke dompet pribadi.

## Prasyarat
- Node.js dan npm
- Hardhat

## Instalasi
1. Clone repositori:
   ```bash
   git clone https://github.com/username/oggy-inu-price-manipulation-poc.git
   cd oggy-inu-price-manipulation-poc
