pragma solidity 0.5.13;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "../access/WalletsManagers.sol";
import "../validators/ValidatorsRegistry.sol";
import "./Wallet.sol";
import "./Withdrawals.sol";

/**
 * @title WalletsRegistry
 * WalletsRegistry creates and assigns wallets to validators.
 * The deposits and rewards generated by the validator will be withdrawn to the wallet it was assigned.
 * To reuse wallets multiple times for different validators, a user with an admin
 * role can reset the wallet when all the users have withdrawn their shares.
 */
contract WalletsRegistry is Initializable {
    /**
    * Structure to store information about the wallet assignment.
    * @param unlocked - indicates whether users can withdraw from the wallet.
    * @param validator - the validator wallet is attached to.
    */
    struct WalletAssignment {
        bool unlocked;
        bytes32 validator;
    }

    // Determines whether validator ID (public key hash) has been assigned any wallet.
    // Required to prevent assigning multiple wallets to the same validator.
    mapping(bytes32 => bool) public assignedValidators;

    // Maps wallet address to the information about its assignment.
    mapping(address => WalletAssignment) public wallets;

    // Stores list of available wallets.
    address[] private availableWallets;

    // Address of the Admins contract.
    Admins private admins;

    // Address of the WalletsManagers contract.
    WalletsManagers private walletsManagers;

    // Address of the ValidatorsRegistry contract.
    ValidatorsRegistry private validatorsRegistry;

    // Address of the Withdrawals contract.
    Withdrawals private withdrawals;

    /**
    * Event for tracking wallet new assignment.
    * @param validator - ID (public key hash) of the validator wallet was assigned to.
    * @param wallet - address of the wallet the deposits and rewards will be withdrawn to.
    */
    event WalletAssigned(bytes32 validator, address indexed wallet);

    /**
    * Event for tracking wallet resets.
    * @param wallet - address of the reset wallet.
    */
    event WalletReset(address wallet);

    /**
    * Event for tracking wallet unlocks.
    * @param wallet - address of the unlocked wallet.
    */
    event WalletUnlocked(bytes32 validator, address indexed wallet, uint256 balance);

    /**
    * Constructor for initializing the WalletsRegistry contract.
    * @param _admins - Address of the Admins contract.
    * @param _walletsManagers - Address of the WalletsManagers contract.
    * @param _validatorsRegistry - Address of the Validators Registry contract.
    * @param _withdrawals - Address of the Withdrawals contract.
    */
    function initialize(
        Admins _admins,
        WalletsManagers _walletsManagers,
        ValidatorsRegistry _validatorsRegistry,
        Withdrawals _withdrawals
    )
        public initializer
    {
        admins = _admins;
        walletsManagers = _walletsManagers;
        validatorsRegistry = _validatorsRegistry;
        withdrawals = _withdrawals;
    }

    /**
    * Function for assigning wallets to validators.
    * Can only be called by users with a wallets manager role.
    * @param _validator - ID (public key hash) of the validator wallet should be assigned to.
    */
    function assignWallet(bytes32 _validator) external {
        require(!assignedValidators[_validator], "Validator has already wallet assigned.");

        (uint256 validatorAmount, ,) = validatorsRegistry.validators(_validator);
        require(validatorAmount != 0, "Validator does not have deposit amount.");
        require(walletsManagers.isManager(msg.sender), "Permission denied.");

        address wallet;
        // Check whether previous wallets could be reused
        if (availableWallets.length > 0) {
            wallet = availableWallets[availableWallets.length - 1];
            availableWallets.pop();
        } else {
            wallet = address(new Wallet(withdrawals));
        }

        wallets[wallet].validator = _validator;
        assignedValidators[_validator] = true;

        emit WalletAssigned(_validator, wallet);
    }

    /**
    * Function for resetting wallets.
    * Can only be called by users with an admin role.
    * Must be called only when all the users have withdrawn their shares.
    * @param _wallet - Address of the wallet to reset.
    */
    function resetWallet(address _wallet) external {
        require(admins.isAdmin(msg.sender), "Permission denied.");
        require(wallets[_wallet].validator[0] != 0, "Wallet has been already reset.");

        delete wallets[_wallet];
        availableWallets.push(_wallet);
        emit WalletReset(_wallet);
    }

    /**
    * Function for unlocking wallets.
    * Can only be called by Withdrawals contract.
    * Users will be able to withdraw their shares from unlocked wallet.
    * @param _wallet - Address of the wallet to unlock.
    */
    function unlockWallet(address payable _wallet) external {
        require(msg.sender == address(withdrawals), "Permission denied.");
        require(!wallets[_wallet].unlocked, "Wallet is already unlocked.");

        wallets[_wallet].unlocked = true;
        emit WalletUnlocked(wallets[_wallet].validator, _wallet, _wallet.balance);
    }
}
