pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./library/BasisPoints.sol";


contract ForwardStaking is Initializable, Ownable {
    using BasisPoints for uint;
    using SafeMath for uint;

    uint256 constant internal DISTRIBUTION_MULTIPLIER = 2 ** 64;

    uint public stakingTaxBP;
    uint public unStakingTaxBP;
    IERC20 private forwardToken;

    mapping(address => uint) public stakeValue;
    mapping(address => uint) private stakerPayouts;

    uint public totalTaxDistribution;
    uint public totalStaked;
    uint public totalStakers;
    uint private profitPerShare;
    uint private emptyStakeTokens; //These are tokens given to the contract when there are no stakers.

    event OnTaxDistribute(uint amountSent);
    event OnStake(address sender, uint amount, uint tax);
    event OnUnstake(address sender, uint amount, uint tax);

    modifier onlyForwardToken {
        require(msg.sender == address(forwardToken), "Can only be called by ForwardToken contract.");
        _;
    }

    function initialize(uint _stakingTaxBP, uint _ustakingTaxBP, IERC20 _forwardToken) public initializer {
        stakingTaxBP = _stakingTaxBP;
        unStakingTaxBP = _ustakingTaxBP;
        forwardToken = _forwardToken;
    }

    function handleTaxDistribution(uint amount) public onlyForwardToken {
        totalTaxDistribution = totalTaxDistribution.add(amount);
        _increaseProfitPerShare(amount);
        emit OnTaxDistribute(amount);
    }

    function stake(uint amount) public {
        require(amount >= 1e18, "Must stake at least one FWC.");
        require(forwardToken.balanceOf(msg.sender) >= amount, "Cannot stake more FWC than you hold unstaked.");
        uint tax = findTaxAmount(amount);
        uint stakeAmount = amount.sub(tax);
        totalStakers = totalStakers.add(1);
        totalStaked = totalStaked.add(stakeAmount);
        stakeValue[msg.sender] = stakeValue[msg.sender].add(stakeAmount);
        uint basePayout = profitPerShare.mul(stakeAmount);
        if (basePayout >= tax) {
            stakerPayouts[msg.sender] = stakerPayouts[msg.sender].add(
                profitPerShare.mul(stakeAmount).sub(tax.mul(DISTRIBUTION_MULTIPLIER))
            );
        }
        require(forwardToken.transferFrom(msg.sender, address(this), amount), "Stake failed due to failed transfer.");
        emit OnStake(msg.sender, amount, tax);
    }

    function unstake(uint amount) public {
        require(amount >= 1e18, "Must unstake at least one FWC.");
        require(stakeValue[msg.sender] >= amount, "Cannot unstake more FWC than you have staked.");
        uint tax = findTaxAmount(amount);
        uint earnings = amount.sub(tax);
        if (stakeValue[msg.sender] == amount) totalStakers = totalStakers.sub(1);
        totalStaked = totalStaked.sub(amount);
        stakeValue[msg.sender] = stakeValue[msg.sender].sub(amount);
        uint payout = profitPerShare.mul(amount).add(tax.mul(DISTRIBUTION_MULTIPLIER));
        if (stakerPayouts[msg.sender] <= payout) {
            stakerPayouts[msg.sender] = 0;
        } else {
            stakerPayouts[msg.sender] = stakerPayouts[msg.sender].sub(payout);
        }
        _increaseProfitPerShare(tax);
        require(
            forwardToken.transferFrom(address(this), msg.sender, earnings),
            "Unstake failed due to failed transfer."
        );
        emit OnUnstake(msg.sender, amount, tax);
    }

    function dividendsOf(address staker) public view returns (uint) {
        return (profitPerShare.mul(stakeValue[staker]).sub(stakerPayouts[staker])).div(DISTRIBUTION_MULTIPLIER);
    }

    function _increaseProfitPerShare(uint amount) internal {
        if (totalStaked != 0) {
            if (emptyStakeTokens != 0) {
                amount = amount.add(emptyStakeTokens);
                emptyStakeTokens = 0;
            }
            profitPerShare = profitPerShare.add(amount.mul(DISTRIBUTION_MULTIPLIER).div(totalStaked));
        } else {
            emptyStakeTokens = emptyStakeTokens.add(amount);
        }
    }

    function findTaxAmount(uint value) internal pure returns (uint) {
        return value.mulBP(value);
    }

}
