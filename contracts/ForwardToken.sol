pragma solidity 0.5.17;
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/StandaloneERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./library/BasisPoints.sol";
import "./ForwardStaking.sol";


contract ForwardToken is Initializable, ERC20, ERC20Burnable, StandaloneERC20, Ownable {
    using BasisPoints for uint;
    using SafeMath for uint;

    uint public taxBP;
    bool public isTaxActive = false;
    ForwardStaking private forwardStaking;
    mapping(address => bool) public trustedContracts;

    function initialize(
        string memory name, string memory symbol, uint8 decimals,
        address[] memory minters, address[] memory pausers,
        address[] memory _trustedContracts,
        uint _taxBP, ForwardStaking _forwardStaking
    ) public initializer {
        Ownable.initialize(msg.sender);
        StandaloneERC20.initialize(name, symbol, decimals, minters, pausers);
        taxBP = _taxBP;
        forwardStaking = _forwardStaking;
        addTrustedContract(address(forwardStaking));
        for (uint256 i = 0; i < minters.length; ++i) {
            addTrustedContract(_trustedContracts[i]);
        }
    }

    function findTaxAmount(uint value) public pure returns (uint) {
        return value.mulBP(value);
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        isTaxActive ?
            _transferWithTax(msg.sender, recipient, amount) :
            _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        isTaxActive ?
            _transferWithTax(sender, recipient, amount) :
            _transfer(sender, recipient, amount);
        if (trustedContracts[msg.sender]) return true;
        approve
        (
            msg.sender,
            allowance(
                sender,
                msg.sender
            ).sub(amount)
        );
        return true;
    }

    function setTaxRate(uint valueBP) public onlyOwner {
        require(valueBP < 10000, "Tax connot be over 100% (10000 BP)");
        taxBP = valueBP;
    }

    function setIsTaxActive(bool value) public onlyOwner {
        isTaxActive = value;
    }

    function addTrustedContract(address contractAddress) public onlyOwner {
        trustedContracts[contractAddress] = true;
    }

    function removeTrustedContract(address contractAddress) public onlyOwner {
        trustedContracts[contractAddress] = false;
    }

    function _transferWithTax(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 tokensToTax = findTaxAmount(amount);
        uint256 tokensToTransfer = amount.sub(tokensToTax);

        _transfer(sender, address(forwardStaking), tokensToTax);
        _transfer(sender, recipient, tokensToTransfer);
        forwardStaking.handleTaxDistribution(tokensToTax);
    }
}
