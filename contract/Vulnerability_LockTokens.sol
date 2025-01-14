// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./KPNToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


contract LockTokens is AccessControl{
    using SafeERC20 for IERC20;

    IMultiSigWallet public immutable multiSigWallet;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address[] private adminAddresses; // Track addresses with ADMIN_ROLE

    // KPN Token Contract
    KPNToken private KPN;
    uint256 public totalLockedTokens; // total value locked
    uint256 public usdtVault;         // USDT vault (USDT)
    address private USDT; // USDT token address - can be replaced with whatever ERC20 token you would like to use
    
    // tier cut off amounts
    uint256 public constant tier1Cutoff = 750000 * (10**18);
    uint256 public constant tier2Cutoff = 1250000 * (10**18);
    uint256 public constant tier3Cutoff = 3000000 * (10**18);
    uint256 public constant tier4Cutoff = 5000000 * (10**18);
    uint256 public constant tier5Cutoff = 7500000 * (10**18);
    uint256 public constant tier6Cutoff = 12500000 * (10**18);

    // tier time locks
    uint256 public constant locktime1 = 180 days; 
    uint256 public constant locktime2 = 365 days;
    uint256 public constant locktime3 = 730 days;



    // fixed reward rate per tier and month
    // TIER 1
    uint256 public tier1mon6 = 750 * (10**6);
    uint256 public tier1mon12 = 1800 * (10**6);
    uint256 public tier1mon24 = 4500 * (10**6);

    // TIER 2
    uint256 public tier2mon6 = 1500 * (10**6);
    uint256 public tier2mon12 = 3500 * (10**6);
    uint256 public tier2mon24 = 8000 * (10**6);

    
    // TIER 3
    uint256 public tier3mon6 = 4200 * (10**6);
    uint256 public tier3mon12 = 9000 * (10**6);
    uint256 public tier3mon24 = 21000 * (10**6);
    
    // TIER 4
    uint256 public tier4mon6 = 8000 * (10**6);
    uint256 public tier4mon12 = 17000 * (10**6);
    uint256 public tier4mon24 = 37000 * (10**6);
    
    // TIER 5
    uint256 public tier5mon6 = 13500 * (10**6);
    uint256 public tier5mon12 = 28500 * (10**6);
    uint256 public tier5mon24 = 58500 * (10**6);
    
    // TIER 6
    uint256 public tier6mon6 = 25000 * (10**6);
    uint256 public tier6mon12 = 50000 * (10**6);
    uint256 public tier6mon24 = 112500 * (10**6);

    // struct to track locked stakes
    struct LockAmount{
        uint256 lockTime;
        uint256 amount;
        uint256 timestamp;
        uint rewardAmount;
    }

    address[] public usersWithActiveLocks;
    mapping(address => bool) private hasActiveLock;
    //mapping of user address to locked amount struct for locked up tokens
    mapping(address=>LockAmount) public lockedBalances;

    // events for locking withdrawing and paying rewards
    event TokensLocked(address indexed sender, uint256 lockDuration);
    event TokensWithdrawn(address indexed sender, uint256 timestamp);
    event RewardsPaid(address indexed receiver, uint256 amount);
    event LockCancelled(address indexed staker, uint256 amount);
    event InsufficientUSDTForRewards(address indexed  to, uint256 rewardAmount);

    // sets kpn token and rewards token and deployer as owner
    constructor(address kpntoken, address rewardsToken, address multiSigWalletAddress){
        require(kpntoken != address(0) && rewardsToken != address(0) && multiSigWalletAddress != address(0), "Address zero not allowed!");
        multiSigWallet = IMultiSigWallet(multiSigWalletAddress);
        KPN = KPNToken(kpntoken);
        USDT = rewardsToken;

        address[] memory owners = multiSigWallet.getOwners();
        require(owners.length >= 3, "MultiSig wallet must have at least three owners");

        _grantRole(DEFAULT_ADMIN_ROLE, multiSigWalletAddress); // Assigns the multiSigWalletAddress the default admin role
        _grantRole(ADMIN_ROLE, multiSigWalletAddress);
        _grantRole(ADMIN_ROLE, owners[0]);
    

        adminAddresses.push(multiSigWalletAddress); // Initialize adminAddresses with the multiSigWalletAddress address
        adminAddresses.push(owners[0]);

    }



    function stake(uint amount, uint timeFrame) public {
        require(amount > 0, "ERC20: Cannot send 0 tokens");
        require(amount >= tier1Cutoff, "Locking ERC20: Please send minimum token amount");
        require(timeFrame == locktime1 || timeFrame == locktime2 || timeFrame == locktime3, "Locking ERC20: Please select proper time frame");
        
        if(lockedBalances[msg.sender].amount > 0){
            uint256 refund = lockedBalances[msg.sender].amount;
            lockedBalances[msg.sender].amount = 0;
            lockedBalances[msg.sender].lockTime = 0;
            IERC20(KPN).safeTransfer(msg.sender, refund);
            emit TokensWithdrawn(msg.sender, block.timestamp);
        }

        if(amount >= tier1Cutoff && amount <tier2Cutoff){
            uint256 extra = amount - tier1Cutoff; // get extra off of sent amount
            uint256 lockAmount = amount - extra; // calculate the lock amount back to tier amount
            uint rewardAmount = _calcRewardAmount(timeFrame, lockAmount);
            LockAmount memory newLock = LockAmount(timeFrame, lockAmount, block.timestamp, rewardAmount); // set the tokens into locked status

            lockedBalances[msg.sender] = newLock;
            totalLockedTokens+= lockAmount;

            require(IERC20(USDT).balanceOf(address(this)) - usdtVault >= rewardAmount,"Not enough USDT in contract to cover rewards");
            usdtVault += rewardAmount;

            IERC20(KPN).safeTransferFrom(msg.sender, address(this), lockAmount);

        }else if (amount >= tier2Cutoff && amount <tier3Cutoff){
            uint256 extra = amount - tier2Cutoff; // get extra off of sent amount
            uint256 lockAmount = amount - extra; // calculate the lock amount back to tier amount

            uint rewardAmount = _calcRewardAmount(timeFrame, lockAmount);
            LockAmount memory newLock = LockAmount(timeFrame, lockAmount, block.timestamp, rewardAmount); // set the tokens into locked status

            require(IERC20(USDT).balanceOf(address(this)) - usdtVault >= rewardAmount,"Not enough USDT in contract to cover rewards");
            usdtVault += rewardAmount;

            lockedBalances[msg.sender] = newLock;
            totalLockedTokens+= lockAmount;
            IERC20(KPN).safeTransferFrom(msg.sender, address(this), lockAmount);

        }else if (amount >= tier3Cutoff && amount < tier4Cutoff){
            uint256 extra = amount - tier3Cutoff; // get extra off of sent amount
            uint256 lockAmount = amount - extra; // calculate the lock amount back to tier amount
            uint rewardAmount = _calcRewardAmount(timeFrame, lockAmount);
            LockAmount memory newLock = LockAmount(timeFrame, lockAmount, block.timestamp, rewardAmount); // set the tokens into locked status
            
            require(IERC20(USDT).balanceOf(address(this)) - usdtVault >= rewardAmount,"Not enough USDT in contract to cover rewards");
            usdtVault += rewardAmount;
            
            lockedBalances[msg.sender] = newLock;
            totalLockedTokens+= lockAmount;
            IERC20(KPN).safeTransferFrom(msg.sender, address(this), lockAmount);

        } else if (amount >= tier4Cutoff && amount < tier5Cutoff){
            uint256 extra = amount - tier4Cutoff; // get extra off of sent amount
            uint256 lockAmount = amount - extra; // calculate the lock amount back to tier amount
            uint rewardAmount = _calcRewardAmount(timeFrame, lockAmount);
            LockAmount memory newLock = LockAmount(timeFrame, lockAmount, block.timestamp, rewardAmount); // set the tokens into locked status
            
            require(IERC20(USDT).balanceOf(address(this)) - usdtVault >= rewardAmount,"Not enough USDT in contract to cover rewards");
            usdtVault += rewardAmount;

            lockedBalances[msg.sender] = newLock;
            totalLockedTokens+= lockAmount;
            IERC20(KPN).safeTransferFrom(msg.sender, address(this), lockAmount);

        } else if (amount >= tier5Cutoff && amount < tier6Cutoff){
            uint256 extra = amount - tier5Cutoff; // get extra off of sent amount
            uint256 lockAmount = amount - extra; // calculate the lock amount back to tier amount

            uint rewardAmount = _calcRewardAmount(timeFrame, lockAmount);
            LockAmount memory newLock = LockAmount(timeFrame, lockAmount, block.timestamp, rewardAmount); // set the tokens into locked status
            
            require(IERC20(USDT).balanceOf(address(this)) - usdtVault >= rewardAmount,"Not enough USDT in contract to cover rewards");
            usdtVault += rewardAmount;

            lockedBalances[msg.sender] = newLock;
            totalLockedTokens+= lockAmount;
            IERC20(KPN).safeTransferFrom(msg.sender, address(this), lockAmount);

        } else {
            // top tier no lock no lock cap
            uint256 extra = amount - tier6Cutoff; // get extra off of sent amount
            uint256 lockAmount = amount - extra;
            uint rewardAmount = _calcRewardAmount(timeFrame, lockAmount);
            LockAmount memory newLock = LockAmount(timeFrame, amount, block.timestamp, rewardAmount); // set the tokens into locked status
            
            require(IERC20(USDT).balanceOf(address(this)) - usdtVault >= rewardAmount,"Not enough USDT in contract to cover rewards");
            usdtVault += rewardAmount;

            lockedBalances[msg.sender] = newLock;
            totalLockedTokens+= amount;
            IERC20(KPN).safeTransferFrom(msg.sender, address(this), amount);

        }
        if (!hasActiveLock[msg.sender]) {
            usersWithActiveLocks.push(msg.sender);
            hasActiveLock[msg.sender] = true;
        }
        emit TokensLocked(msg.sender, timeFrame);
    }

    function cancelStake() public {
        require(block.timestamp < lockedBalances[msg.sender].lockTime + lockedBalances[msg.sender].timestamp, "ERC20: Cannot Cancel Completed Stake");
        require(lockedBalances[msg.sender].amount > 0, "ERC20: No Funds Locked");
        uint256 tokenAmount = lockedBalances[msg.sender].amount; // gets local copy of variable to save on gas cost
        require(KPN.balanceOf(address(this)) >= tokenAmount, "ERC20: Contract Balance Too Low");

        totalLockedTokens -= tokenAmount;
        // deletes the staking struct
        delete lockedBalances[msg.sender];
        if (hasActiveLock[msg.sender]) {
            _removeAddressFromArray(msg.sender);
            hasActiveLock[msg.sender] = false;
        }

        IERC20(KPN).safeTransfer(msg.sender, tokenAmount);

        emit LockCancelled(msg.sender, tokenAmount);
    }

    function withdrawLocked() public {
        require(block.timestamp > lockedBalances[msg.sender].lockTime + lockedBalances[msg.sender].timestamp, "ERC20: Time Lock not complete");
        require(lockedBalances[msg.sender].amount > 0, "ERC20: No Funds Locked");
        uint256 tokenAmount = lockedBalances[msg.sender].amount;
        uint256 rewardAmount = lockedBalances[msg.sender].rewardAmount;

        // LockAmount memory lockStruct = lockedBalances[msg.sender];
        totalLockedTokens -= tokenAmount;
        delete lockedBalances[msg.sender];
        if (hasActiveLock[msg.sender]) {
            _removeAddressFromArray(msg.sender);
            hasActiveLock[msg.sender] = false;
        }
        // safeTransfer KPN tokens back to the user
        IERC20(KPN).safeTransfer(msg.sender, tokenAmount);

        // Attempt to pay USDT rewards separately
        _tryPayUSDT(msg.sender, rewardAmount);

        emit TokensWithdrawn(msg.sender, block.timestamp);
    }

    function _tryPayUSDT(address to, uint256 rewardAmount) private {
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        if (usdtBalance >= rewardAmount) {
            IERC20(USDT).safeTransfer(to, rewardAmount);
            usdtVault -= rewardAmount;
        } else {
            emit InsufficientUSDTForRewards(to, rewardAmount);
        }
    }


    function _calcRewardAmount(uint256 timeFrame, uint stakeAmount) internal view returns(uint tier){
        if(stakeAmount >= tier1Cutoff && stakeAmount < tier2Cutoff){
            if(timeFrame == locktime1){
                return tier1mon6;
            }else if (timeFrame == locktime2){
                return tier1mon12;
            }else if (timeFrame == locktime3){
                return tier1mon24;
            }
        } else if (stakeAmount >= tier2Cutoff && stakeAmount < tier3Cutoff){
            if(timeFrame == locktime1){
                return tier2mon6;
            }else if (timeFrame == locktime2){
                return tier2mon12;
            }else if (timeFrame == locktime3){
                return tier2mon24;
            }
        }else if (stakeAmount >= tier3Cutoff && stakeAmount < tier4Cutoff){
            if(timeFrame == locktime1){
                return tier3mon6;
            }else if (timeFrame == locktime2){
                return tier3mon12;
            }else if (timeFrame == locktime3){
                return tier3mon24;
            }
        }else if (stakeAmount >= tier4Cutoff && stakeAmount < tier5Cutoff){
            if(timeFrame == locktime1){
                return tier4mon6;
            }else if (timeFrame == locktime2){
                return tier4mon12;
            }else if (timeFrame == locktime3){
                return tier4mon24;
            }
        }else if (stakeAmount >= tier5Cutoff && stakeAmount < tier6Cutoff){
            if(timeFrame == locktime1){
                return tier5mon6;
            }else if (timeFrame == locktime2){
                return tier5mon12;
            }else if (timeFrame == locktime3){
                return tier5mon24;
            }
        }else if (stakeAmount >= tier6Cutoff){
            if(timeFrame == locktime1){
                return tier6mon6;
            }else if (timeFrame == locktime2){
                return tier6mon12;
            }else if (timeFrame == locktime3){
                return tier6mon24;
            }
        }
    }

    // set the rewards token address labeled as USDT
    function setUSDTAddress(address _usdt) public onlyRole(ADMIN_ROLE){
        require(_usdt != address(0), "USDT address zero not allowed!");
        USDT = _usdt;
    }
    function getStakedBalance(address target) public view returns(LockAmount memory){
        return lockedBalances[target];
    }

    function setTier1Rewards(uint rate6mon, uint rate12mon, uint rate24) public onlyRole(ADMIN_ROLE){
        tier1mon6 = rate6mon;
        tier1mon12 = rate12mon;
        tier1mon24 = rate24;
    }
    function setTier2Rewards(uint rate6mon, uint rate12mon, uint rate24) public onlyRole(ADMIN_ROLE){
        tier2mon6 = rate6mon;
        tier2mon12 = rate12mon;
        tier2mon24 = rate24;
    }
    function setTier3Rewards(uint rate6mon, uint rate12mon, uint rate24) public onlyRole(ADMIN_ROLE){
        tier3mon6 = rate6mon;
        tier3mon12 = rate12mon;
        tier3mon24 = rate24;
    }
    function setTier4Rewards(uint rate6mon, uint rate12mon, uint rate24) public onlyRole(ADMIN_ROLE){
        tier4mon6 = rate6mon;
        tier4mon12 = rate12mon;
        tier4mon24 = rate24;
    }
    function setTier5Rewards(uint rate6mon, uint rate12mon, uint rate24) public onlyRole(ADMIN_ROLE){
        tier5mon6 = rate6mon;
        tier5mon12 = rate12mon;
        tier5mon24 = rate24;
    }
    function setTier6Rewards(uint rate6mon, uint rate12mon, uint rate24) public onlyRole(ADMIN_ROLE){
        tier6mon6 = rate6mon;
        tier6mon12 = rate12mon;
        tier6mon24 = rate24;
    }

    // Override grantRole and revokeRole to track role membership
    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        super.grantRole(role, account);
        if (role == ADMIN_ROLE && !_isInArray(account, adminAddresses)) {
            adminAddresses.push(account);
        } else {
            revert("Role not found!");
        }
    }

    function revokeRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        super.revokeRole(role, account);
        if (role == ADMIN_ROLE) {
            _removeFromArray(account, adminAddresses);
        } else {
            revert("Role not found!");
        }
    }

    function getAdminAddresses() public view returns (address[] memory) {
        return adminAddresses;
    }

    // Helper function to check if an address is in an array
    function _isInArray(address account, address[] storage array) private view returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == account) {
                return true;
            }
        }
        return false;
    }

    // Helper function to remove an address from an array
    function _removeFromArray(address account, address[] storage array) private {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == account) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    function withdrawUSDTAdmin(uint256 amount) external onlyRole(ADMIN_ROLE){
        require(IERC20(USDT).balanceOf(address(this)) - usdtVault >= amount , "Not enough USDT");
        IERC20(USDT).safeTransfer(msg.sender,amount);
    }

    function getAllActiveLocks() external view returns (address[] memory, uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory) {
        uint256 length = usersWithActiveLocks.length;
        uint256[] memory lockTimes = new uint256[](length);
        uint256[] memory amounts = new uint256[](length);
        uint256[] memory timestamps = new uint256[](length);
        uint256[] memory rewardAmounts = new uint256[](length);

        for (uint i = 0; i < length; i++) {
            address user = usersWithActiveLocks[i];
            LockAmount memory lockDetail = lockedBalances[user];
            lockTimes[i] = lockDetail.lockTime;
            amounts[i] = lockDetail.amount;
            timestamps[i] = lockDetail.timestamp;
            rewardAmounts[i] = lockDetail.rewardAmount;
        }

        return (usersWithActiveLocks, lockTimes, amounts, timestamps, rewardAmounts);
    }

    function _removeAddressFromArray(address user) private {
        uint256 length = usersWithActiveLocks.length;
        for (uint256 i = 0; i < length; i++) {
            if (usersWithActiveLocks[i] == user) {
                usersWithActiveLocks[i] = usersWithActiveLocks[length - 1];
                usersWithActiveLocks.pop();
                break;
            }
        }
    }
}
