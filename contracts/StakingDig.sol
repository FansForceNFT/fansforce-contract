// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract StakingDig is Initializable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20Metadata;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        bool inBlackList;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20Metadata lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. FFNs to distribute per block.
        uint256 lastRewardBlockTime;  // Last block number that FFNs distribution occurs.
        uint256 accRewordPerShare; // Accumulated FFNs per share, times accRewardDecimal. See below.
    }

    // The REWARD TOKEN
    IERC20Metadata public rewardToken;

    // adminAddress
    address public adminAddress;

    // FFN tokens created per block.
    uint256 public rewardPerPeriod;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // limit 1000 LP here
    uint256 public limitAmount;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when FFN mining starts.
    uint256 public startBlockTime;
    // The block number when FFN mining ends.
    uint256 public bonusEndBlockTime;
    // 每份累计奖励精度扩大因子
    uint256 public accRewardDecimal;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 lpSupply, uint256 accRewordPerShare, uint256 lastRewardBlockTime);

    constructor(){}

    //init func -- cannot be call for twice or more
    function __StakingDig_init_(
        IERC20Metadata _lp,
        IERC20Metadata _rewardToken,
        uint256 _rewardPerPeriod,
        uint256 _startBlockTime,
        uint256 _bonusEndBlockTime,
        address _adminAddress,
        uint256 _limitAmount
    ) public initializer {
        ensureAccRewardDecimal(_lp, _rewardPerPeriod);
        rewardToken = _rewardToken;
        rewardPerPeriod = _rewardPerPeriod;
        startBlockTime = _startBlockTime;
        bonusEndBlockTime = _bonusEndBlockTime;
        adminAddress = _adminAddress;
        limitAmount = _limitAmount;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken : _lp,
            allocPoint : 1000,
            lastRewardBlockTime : startBlockTime,
            accRewordPerShare : 0
        }));

        totalAllocPoint = 10000;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    //ensure accRewardDecimal
    function ensureAccRewardDecimal(IERC20Metadata _lp, uint256 _rewardPerPeriod)
    internal returns(uint256){
        //精度保障：需保障每个月的每份奖励累计不能超过10^60, 每秒的每份奖励累计不能低于100（需充分考虑每秒奖励总数和质押总数）
        //质押总数按1万亿（ (10**12) * (10**decimal) ）计
        //每秒的每份奖励累计不能低于100
        accRewardDecimal = 10 ** 28;
        require((_rewardPerPeriod * accRewardDecimal) / (10 ** (12 + _lp.decimals())) > 100,
            "ensureAccRewardDecimal fail");
        return accRewardDecimal;
    }

    // Update admin address by the previous dev.
    function setAdmin(address _adminAddress) public onlyAdmin {
        adminAddress = _adminAddress;
    }

    function setBlackList(address _blacklistAddress) public onlyAdmin {
        userInfo[_blacklistAddress].inBlackList = true;
    }

    function removeBlackList(address _blacklistAddress) public onlyAdmin {
        userInfo[_blacklistAddress].inBlackList = false;
    }

    // Set the limit amount. Can only be called by the owner.
    function setLimitAmount(uint256 _amount) public onlyAdmin {
        limitAmount = _amount;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlockTime) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlockTime) {
            return 0;
        } else {
            return bonusEndBlockTime.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = pool.accRewordPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardBlockTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlockTime, block.timestamp);
            uint256 reward = multiplier.mul(rewardPerPeriod).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(reward.mul(accRewardDecimal).div(lpSupply));
        }
        return user.amount.mul(accRewardPerShare).div(accRewardDecimal).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardBlockTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlockTime = block.timestamp;
            return;
        }
        //时间差（秒）
        uint256 multiplier = getMultiplier(pool.lastRewardBlockTime, block.timestamp);
        //当前时段奖励 = 每秒奖励 * 时间差
        //每秒奖励 = 每10秒奖励/10
        uint256 cakeReward = multiplier.mul(rewardPerPeriod).mul(pool.allocPoint).div(totalAllocPoint);
        //每份奖励累计（乘过精度扩大因子，用户计算奖励时需除掉） = 之前每份奖励累计 + (每秒奖励*精度扩大因子/质押币个数)
        //！！！！注意：需保障每个月的每份奖励累计不能超过10^60, 每秒的每份奖励累计不能低于100（需充分考虑每秒奖励总数和质押总数）
        pool.accRewordPerShare = pool.accRewordPerShare.add(cakeReward.mul(accRewardDecimal).div(lpSupply));
        //更新最新累计计算时间
        pool.lastRewardBlockTime = block.timestamp;
        emit LogUpdatePool(lpSupply, pool.accRewordPerShare, pool.lastRewardBlockTime);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Stake tokens to SmartChef
    function deposit(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];

        require(user.amount.add(_amount) <= limitAmount, 'exceed the top');
        require(!user.inBlackList, 'in black list');
        //更新质押池
        updatePool(0);
        //奖励结算
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewordPerShare).div(accRewardDecimal).sub(user.rewardDebt);
            if (pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }
        //充币质押
        if (_amount > 0) {
            assert(pool.lpToken.transferFrom(msg.sender, address(this), _amount));
            user.amount = user.amount.add(_amount);
        }
        //更新奖励负债
        user.rewardDebt = user.amount.mul(pool.accRewordPerShare).div(accRewardDecimal);

        emit Deposit(msg.sender, _amount);
    }

    // Withdraw tokens from STAKING.
    function withdraw(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        //更新质押池
        updatePool(0);
        //奖励结算
        uint256 pending = user.amount.mul(pool.accRewordPerShare).div(accRewardDecimal).sub(user.rewardDebt);
        if (pending > 0 && !user.inBlackList) {
            //发奖励币
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        //提币解除质压
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            assert(pool.lpToken.transfer(address(msg.sender), _amount));
        }
        //更新奖励负债
        user.rewardDebt = user.amount.mul(pool.accRewordPerShare).div(accRewardDecimal);

        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) public onlyAdmin {
        require(_amount <= rewardToken.balanceOf(address(this)), 'not enough token');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    // Withdraw wrong deposited token. EMERGENCY ONLY.（紧急提走错充币）
    function emergencyTokenWithdraw(address _tokenAddress, uint256 _amount) public onlyAdmin {
        IERC20Metadata _token = IERC20Metadata(_tokenAddress);
        require(_amount <= _token.balanceOf(address(this)), 'not enough token');
        _token.safeTransfer(address(msg.sender), _amount);
    }

    uint256[39] private __gap;
}
