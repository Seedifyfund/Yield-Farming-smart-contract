pragma solidity 0.5.16;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

pragma solidity 0.5.16;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}

pragma solidity 0.5.16;

contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor() internal {}

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// File: @openzeppelin/contracts/ownership/Ownable.sol

pragma solidity 0.5.16;

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() internal {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

pragma solidity 0.5.16;

contract SMD_v5 is Ownable {
    using SafeMath for uint256;

    address public tokenAddress;
    address public rewardTokenAddress;
    uint256 public stakedTotal;
    uint256 public stakedBalance;
    uint256 public rewardBalance;
    uint256 public totalReward;
    uint256 public startingBlock;
    uint256 public endingBlock;
    uint256 public increaseBlock; //For Local testing purposes only
    uint256 public period;
    uint256 public accShare;
    uint256 public lastRewardBlock;
    bool public isPaused;

    IERC20 public ERC20Interface;

    struct Deposits {
        uint256 amount;
        uint256 initialStake;
        uint256 latestClaim;
        uint256 userAccShare;
        uint256 currentPeriod;
    }

    struct periodDetails {
        uint256 period;
        uint256 accShare;
        uint256 rewPerBlock;
        uint256 startingBlock;
        uint256 endingBlock;
    }

    mapping(address => Deposits) private deposits;
    mapping(address => bool) public isPaid;
    mapping(address => bool) public hasStaked;
    mapping(uint256 => periodDetails) private endAccShare;

    event Staked(
        address indexed token,
        address indexed staker_,
        uint256 stakedAmount_
    );
    event PaidOut(
        address indexed token,
        address indexed rewardToken,
        address indexed staker_,
        uint256 amount_,
        uint256 reward_
    );

    constructor(address _tokenAddress, address _rewardTokenAddress)
        public
        Ownable()
    {
        require(_tokenAddress != address(0), "Zero token address");
        tokenAddress = _tokenAddress;
        require(_rewardTokenAddress != address(0), "Zero reward token address");
        rewardTokenAddress = _rewardTokenAddress;
        isPaused = true;
    }

    function incBlock() public {
        increaseBlock++;
    } // For Local testing purposes only

    /*
        -   To set the start and end blocks for each period
    */

    function setStartEnd(uint256 _start, uint256 _end) private {
        // require(
        //     _start > currentBlock(),
        //     "Start should be more than current block"
        // );
        // require(_end > _start, "End block should be greater than start");
        require(totalReward > 0, "Add rewards for this period");
        startingBlock = _start;
        endingBlock = _end;
        period++;
        isPaused = false;
        lastRewardBlock = _start;
    }

    function addReward(uint256 _rewardAmount)
        private
        _hasAllowance(msg.sender, _rewardAmount, rewardTokenAddress)
        returns (bool)
    {
        // require(_rewardAmount > 0, "Reward must be positive");
        address from = msg.sender;
        if (!_payMe(from, _rewardAmount, rewardTokenAddress)) {
            return false;
        }

        totalReward += _rewardAmount;
        rewardBalance += _rewardAmount;
        return true;
    }

    /*
        -   To reset the contract at the end of each period.
    */

    function reset() private {
        require(block.number > endingBlock, "Wait till end of this period");
        updateShare();
        endAccShare[period] = periodDetails(
            period,
            accShare,
            rewPerBlock(),
            startingBlock,
            endingBlock
        );
        totalReward = 0;
        stakedBalance = 0;
        isPaused = true;
    }

    function resetAndsetStartEndBlock(
        uint256 _rewardAmount,
        uint256 _start,
        uint256 _end
    ) external onlyOwner returns (bool) {
        require(
            _start > currentBlock(),
            "Start should be more than current block"
        );
        require(_end > _start, "End block should be greater than start");
        require(_rewardAmount > 0, "Reward must be positive");
        reset();
        bool rewardAdded = addReward(_rewardAmount);
        require(rewardAdded, "Rewards error");
        setStartEnd(_start, _end);
        return true;
    }

    /*
        -   Function to update rewards and state parameters
    */

    function updateShare() private {
        if (block.number <= lastRewardBlock) {
            return;
        }
        if (stakedBalance == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 noOfBlocks;

        if (block.number >= endingBlock) {
            noOfBlocks = endingBlock.sub(lastRewardBlock);
        } else {
            noOfBlocks = block.number.sub(lastRewardBlock);
        }

        uint256 rewards = noOfBlocks.mul(rewPerBlock());

        accShare = accShare.add((rewards.mul(1e6).div(stakedBalance)));
        if (block.number >= endingBlock) {
            lastRewardBlock = endingBlock;
        } else {
            lastRewardBlock = block.number;
        }
    }

    function rewPerBlock() public view returns (uint256) {
        if (totalReward == 0 || rewardBalance == 0) return 0;
        uint256 rewardperBlock =
            totalReward.div((endingBlock.sub(startingBlock)));
        return (rewardperBlock);
    }

    function stake(uint256 amount)
        external
        _hasAllowance(msg.sender, amount, tokenAddress)
        returns (bool)
    {
        require(!isPaused, "Contract is paused");
        require(
            block.number >= startingBlock && block.number < endingBlock,
            "Invalid period"
        );
        require(amount > 0, "Can't stake 0 amount");
        address from = msg.sender;
        return (_stake(from, amount));
    }

    function _stake(address from, uint256 amount) private returns (bool) {
        updateShare();

        if (!hasStaked[from]) {
            if (!_payMe(from, amount, tokenAddress)) {
                return false;
            }

            deposits[from] = Deposits(
                amount,
                block.number,
                block.number,
                accShare,
                period
            );

            emit Staked(tokenAddress, from, amount);

            stakedBalance += amount;
            stakedTotal += amount;
            hasStaked[from] = true;
            isPaid[from] = false;
            return true;
        } else {
            if (deposits[from].currentPeriod != period) {
                bool renew = _renew(from);
                require(renew, "Error renewing");
            } else {
                bool claim = _claimRewards(from);
                require(claim, "Error paying rewards");
            }

            if (!_payMe(from, amount, tokenAddress)) {
                return false;
            }

            uint256 userAmount = deposits[from].amount;

            deposits[from] = Deposits(
                userAmount.add(amount),
                block.number,
                block.number,
                accShare,
                period
            );

            emit Staked(tokenAddress, from, amount);

            stakedBalance += amount;
            stakedTotal += amount;
            isPaid[from] = false;
            return true;
        }
    }

    function userDeposits(address from)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        if (hasStaked[from]) {
            return (
                deposits[from].amount,
                deposits[from].initialStake,
                deposits[from].latestClaim,
                deposits[from].currentPeriod
            );
        }
    }

    function fetchUserShare(address from) public view returns (uint256) {
        require(hasStaked[from] == true, "No stakes found for user");
        if (stakedBalance == 0) {
            return 0;
        }
        require(
            deposits[from].currentPeriod == period,
            "Please renew in the active valid period"
        );
        uint256 userAmount = deposits[from].amount;
        require(userAmount > 0, "No stakes available for user"); //extra check
        return (userAmount.mul(10000).div(stakedBalance)); //returns percentage upto 2 decimals
    }

    function claimRewards() public returns (bool) {
        require(fetchUserShare(msg.sender) > 0, "No stakes found for user");
        return (_claimRewards(msg.sender));
    }

    function _claimRewards(address from) private returns (bool) {
        uint256 userAccShare = deposits[from].userAccShare;
        updateShare();
        uint256 amount = deposits[from].amount;
        uint256 rewDebt = amount.mul(userAccShare).div(1e6);
        uint256 rew = (amount.mul(accShare).div(1e6)).sub(rewDebt);
        require(rew > 0, "No rewards generated");
        require(rew <= rewardBalance, "Not enough rewards in the contract");
        deposits[from].userAccShare = accShare;
        deposits[from].latestClaim = block.number;
        rewardBalance -= rew;
        bool payRewards = _payDirect(from, rew, rewardTokenAddress);
        require(payRewards, "Rewards transfer failed");
        emit PaidOut(tokenAddress, rewardTokenAddress, from, amount, rew);
        return true;
    }

    function renew() public returns (bool) {
        address from = msg.sender;
        require(!isPaused, "Contract paused");
        require(hasStaked[from], "No stakings found, please stake");
        require(deposits[from].currentPeriod != period, "Already renewed");
        require(
            block.number > startingBlock && block.number < endingBlock,
            "Wrong time"
        );
        return (_renew(from));
    }

    function _renew(address from) private returns (bool) {
        updateShare();
        if (viewOldRewards(from) > 0) {
            bool claimed = claimOldRewards();
            require(claimed, "Error paying old rewards");
        }
        deposits[from].currentPeriod = period;
        deposits[from].initialStake = block.number;
        deposits[from].latestClaim = block.number;
        deposits[from].userAccShare = accShare;
        stakedBalance += deposits[from].amount;
        return true;
    }

    function viewOldRewards(address from) public view returns (uint256) {
        //Local testing purposes only
        require(!isPaused, "Contract paused");
        require(hasStaked[from], "No stakings found, please stake");

        if (deposits[from].currentPeriod == period) {
            return 0;
        }

        uint256 userPeriod = deposits[from].currentPeriod;

        uint256 accShare1 = endAccShare[userPeriod].accShare;
        uint256 userAccShare = deposits[from].userAccShare;

        if (deposits[from].latestClaim > endAccShare[userPeriod].endingBlock)
            return 0;
        uint256 amount = deposits[from].amount;
        uint256 rewDebt = amount.mul(userAccShare).div(1e6);
        uint256 rew = (amount.mul(accShare1).div(1e6)).sub(rewDebt);

        require(rew <= rewardBalance, "Not enough rewards");

        return (rew);
    }

    function claimOldRewards() public returns (bool) {
        address from = msg.sender;
        require(!isPaused, "Contract paused");
        require(hasStaked[from], "No stakings found, please stake");
        require(deposits[from].currentPeriod != period, "Already renewed");

        uint256 userPeriod = deposits[from].currentPeriod;

        uint256 accShare1 = endAccShare[userPeriod].accShare;
        uint256 userAccShare = deposits[from].userAccShare;

        require(
            deposits[from].latestClaim < endAccShare[userPeriod].endingBlock,
            "Already claimed old rewards"
        );
        uint256 amount = deposits[from].amount;
        uint256 rewDebt = amount.mul(userAccShare).div(1e6);
        uint256 rew = (amount.mul(accShare1).div(1e6)).sub(rewDebt);

        require(rew <= rewardBalance, "Not enough rewards");
        deposits[from].latestClaim = endAccShare[userPeriod].endingBlock;
        rewardBalance -= rew;
        bool paidOldRewards = _payDirect(from, rew, rewardTokenAddress);
        require(paidOldRewards, "Error paying");
        emit PaidOut(tokenAddress, rewardTokenAddress, from, amount, rew);
        return true;
    }

    function calculate(address from) public view returns (uint256) {
        if (fetchUserShare(from) == 0) return 0;
        return (_calculate(from));
    }

    function _calculate(address from) private view returns (uint256) {
        uint256 userAccShare = deposits[from].userAccShare;
        uint256 currentAccShare = accShare;
        //Simulating updateShare() to calculate rewards
        if (block.number <= lastRewardBlock) {
            return 0;
        }
        if (stakedBalance == 0) {
            return 0;
        }

        uint256 noOfBlocks;

        if (block.number >= endingBlock) {
            noOfBlocks = endingBlock.sub(lastRewardBlock);
        } else {
            noOfBlocks = block.number.sub(lastRewardBlock);
        }

        uint256 rewards = noOfBlocks.mul(rewPerBlock());

        uint256 newAccShare =
            currentAccShare.add((rewards.mul(1e6).div(stakedBalance)));
        uint256 amount = deposits[from].amount;
        uint256 rewDebt = amount.mul(userAccShare).div(1e6);
        uint256 rew = (amount.mul(newAccShare).div(1e6)).sub(rewDebt);
        return (rew);
    }

    function emergencyWithdraw() external returns (bool) {
        address from = msg.sender;
        require(hasStaked[from] == true, "No stakes available for user");
        require(isPaid[from] == false, "Already Paid");
        return (_withdraw(from));
    }

    function _withdraw(address from) private returns (bool) {
        updateShare();
        uint256 amount = deposits[from].amount;
        if (!isPaused && deposits[from].currentPeriod == period) {
            stakedBalance = stakedBalance.sub(amount);
        }
        isPaid[from] = true;
        hasStaked[from] = false;
        bool paid = _payDirect(from, amount, tokenAddress);
        require(paid, "Error");
        delete deposits[from];
        return true;
    }

    function withdraw() external returns (bool) {
        address from = msg.sender;

        if (deposits[from].currentPeriod == period) {
            if (calculate(from) > 0) {
                bool rewardsPaid = claimRewards();
                require(rewardsPaid, "Error paying rewards");
            }
        }

        if (viewOldRewards(from) > 0) {
            bool oldRewardsPaid = claimOldRewards();
            require(oldRewardsPaid, "Error paying old rewards");
        }
        _withdraw(from);
    }

    // function removeRewards() public returns (bool) {
    //     require(rewardBalance > 0, "No rewards in the pool");
    //     _payDirect(msg.sender, rewardBalance, rewardTokenAddress);
    //     rewardBalance = 0;
    // }  - For Local testing purpose only

    function currentBlock() public view returns (uint256) {
        return (block.number);
    }

    function _payMe(
        address payer,
        uint256 amount,
        address token
    ) private returns (bool) {
        return _payTo(payer, address(this), amount, token);
    }

    function _payTo(
        address allower,
        address receiver,
        uint256 amount,
        address token
    ) private returns (bool) {
        // Request to transfer amount from the contract to receiver.
        // contract does not own the funds, so the allower must have added allowance to the contract
        // Allower is the original owner.
        ERC20Interface = IERC20(token);
        return ERC20Interface.transferFrom(allower, receiver, amount);
    }

    function _payDirect(
        address to,
        uint256 amount,
        address token
    ) private returns (bool) {
        ERC20Interface = IERC20(token);
        return ERC20Interface.transfer(to, amount);
    }

    modifier _hasAllowance(
        address allower,
        uint256 amount,
        address token
    ) {
        // Make sure the allower has provided the right allowance.
        ERC20Interface = IERC20(token);
        uint256 ourAllowance = ERC20Interface.allowance(allower, address(this));
        require(amount <= ourAllowance, "Make sure to add enough allowance");
        _;
    }
}
