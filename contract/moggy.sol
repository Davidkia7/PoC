// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.19;

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract OggyInuRemix is IBEP20 {
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;

    address[] private _excluded;

    bool public tradingEnabled;
    bool public swapEnabled;
    bool private swapping;

    address public pair;
    uint256 public swapTokensAtAmount = 42e13 * 10**9;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;
    address public marketingWallet = 0xA98660D87D3605D000490a43e56b365970c08C93;
    address private owner;

    uint8 private constant _decimals = 9;
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 42e16 * 10**_decimals;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));

    string private constant _name = "Oggy Inu Remix";
    string private constant _symbol = "OGGYR";

    struct Taxes {
        uint256 rfi;
        uint256 marketing;
        uint256 ops;
        uint256 liquidity;
        uint256 dev;
    }

    Taxes public taxes = Taxes(5, 5, 0, 0, 0);

    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier lockTheSwap() {
        swapping = true;
        _;
        swapping = false;
    }

    constructor() {
        owner = msg.sender;
        pair = msg.sender; // Simulasi pair dengan alamat deployer sementara
        _rOwned[owner] = _rTotal;
        _isExcludedFromFee[owner] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[marketingWallet] = true;
        emit Transfer(address(0), owner, _tTotal);
    }

    // Fungsi BEP-20
    function name() public pure returns (string memory) { return _name; }
    function symbol() public pure returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _tTotal; }
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }
    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowances[owner_][spender];
    }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "Transfer exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    function _approve(address owner_, address spender, uint256 amount) private {
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(amount <= balanceOf(from), "Insufficient balance");

        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            require(tradingEnabled, "Trading not active");
        }

        bool canSwap = balanceOf(address(this)) >= swapTokensAtAmount;
        if (!swapping && swapEnabled && canSwap && from != pair && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            swapAndLiquify(swapTokensAtAmount);
        }

        bool takeFee = !swapping && !_isExcludedFromFee[from] && !_isExcludedFromFee[to];
        _tokenTransfer(from, to, amount, takeFee, to == pair);
    }

    function _tokenTransfer(address sender, address recipient, uint256 tAmount, bool takeFee, bool isSell) private {
        valuesFromGetValues memory s = _getValues(tAmount, takeFee, isSell, false);

        if (_isExcluded[sender]) _tOwned[sender] -= tAmount;
        if (_isExcluded[recipient]) _tOwned[recipient] += s.tTransferAmount;

        _rOwned[sender] -= s.rAmount;
        _rOwned[recipient] += s.rTransferAmount;

        if (s.rRfi > 0) _reflectRfi(s.rRfi, s.tRfi);
        if (s.rMarketing > 0) _takeMarketing(s.rMarketing, s.tMarketing);
        if (s.rLiquidity > 0) _takeLiquidity(s.rLiquidity, s.tLiquidity);

        emit Transfer(sender, recipient, s.tTransferAmount);
    }

    struct valuesFromGetValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rRfi;
        uint256 rMarketing;
        uint256 rOps;
        uint256 rLiquidity;
        uint256 rDev;
        uint256 tTransferAmount;
        uint256 tRfi;
        uint256 tMarketing;
        uint256 tOps;
        uint256 tLiquidity;
        uint256 tDev;
    }

    function _getValues(uint256 tAmount, bool takeFee, bool isSell, bool useLaunchTax) private view returns (valuesFromGetValues memory) {
        valuesFromGetValues memory s;
        s.tTransferAmount = tAmount;
        if (!takeFee) return s;

        Taxes memory temp = taxes;
        s.tRfi = (tAmount * temp.rfi) / 100;
        s.tMarketing = (tAmount * temp.marketing) / 100;
        s.tLiquidity = (tAmount * temp.liquidity) / 100;
        s.tTransferAmount = tAmount - s.tRfi - s.tMarketing - s.tLiquidity;

        uint256 currentRate = _getRate();
        s.rAmount = tAmount * currentRate;
        s.rRfi = s.tRfi * currentRate;
        s.rMarketing = s.tMarketing * currentRate;
        s.rLiquidity = s.tLiquidity * currentRate;
        s.rTransferAmount = s.rAmount - s.rRfi - s.rMarketing - s.rLiquidity;
        return s;
    }

    function _reflectRfi(uint256 rRfi, uint256 tRfi) private {
        _rTotal -= rRfi;
    }

    function _takeMarketing(uint256 rMarketing, uint256 tMarketing) private {
        if (_isExcluded[address(this)]) _tOwned[address(this)] += tMarketing;
        _rOwned[address(this)] += rMarketing;
    }

    function _takeLiquidity(uint256 rLiquidity, uint256 tLiquidity) private {
        if (_isExcluded[address(this)]) _tOwned[address(this)] += tLiquidity;
        _rOwned[address(this)] += rLiquidity;
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply -= _rOwned[_excluded[i]];
            tSupply -= _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        return rAmount / _getRate();
    }

    function excludeFromReward(address account) public onlyOwner {
        if (!_isExcluded[account] && _rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function EnableTrading() external onlyOwner {
        tradingEnabled = true;
        swapEnabled = true;
    }

    function updateSwapTokensAtAmount(uint256 amount) external onlyOwner {
        require(amount <= 42e14, "Cannot exceed 1% of total supply");
        swapTokensAtAmount = amount * 10**_decimals;
    }

    function updateMarketingWallet(address newWallet) external onlyOwner {
        marketingWallet = newWallet;
    }

    function swapAndLiquify(uint256 contractBalance) private lockTheSwap {
        uint256 half = contractBalance / 2;
        uint256 otherHalf = contractBalance - half;

        // Simulasi swap dan likuiditas di Remix VM
        uint256 simulatedBNB = half / 10**9; // Dummy conversion rate
        _rOwned[address(this)] -= half; // Kurangi token yang "diswap"
        _rOwned[pair] += otherHalf; // Tambah ke pair sebagai likuiditas
        payable(marketingWallet).transfer(simulatedBNB); // Simulasi kirim BNB

        emit SwapAndLiquify(half, simulatedBNB);
    }

    receive() external payable {}
}
