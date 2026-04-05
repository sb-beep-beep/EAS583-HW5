// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Source is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WARDEN_ROLE = keccak256("BRIDGE_WARDEN_ROLE");

    mapping(address => bool) public approved;
    address[] public tokens;

    event Deposit(address indexed token, address indexed recipient, uint256 amount);
    event Withdrawal(address indexed token, address indexed recipient, uint256 amount);
    event Registration(address indexed token);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(WARDEN_ROLE, admin);
    }

    function deposit(address _token, address _recipient, uint256 _amount) public {
        // Ensure the token is registered for bridging
        require(approved[_token], "Token not approved");

        // Reject zero-value deposits
        require(_amount > 0, "Amount must be > 0");

        // Prevent sending to the zero address on the destination side
        require(_recipient != address(0), "Invalid recipient");

        // Pull the tokens from the depositor into this contract
        require(
            ERC20(_token).transferFrom(msg.sender, address(this), _amount),
            "transferFrom failed"
        );

        // Emit an event so the bridge operator can mint on the destination chain
        emit Deposit(_token, _recipient, _amount);
    }

    function withdraw(address _token, address _recipient, uint256 _amount) public onlyRole(WARDEN_ROLE) {
        // Ensure the token is registered
        require(approved[_token], "Token not approved");

        // Reject zero-value withdrawals
        require(_amount > 0, "Amount must be > 0");

        // Prevent withdrawals to the zero address
        require(_recipient != address(0), "Invalid recipient");

        // Transfer the underlying tokens out of the contract
        require(
            ERC20(_token).transfer(_recipient, _amount),
            "transfer failed"
        );

        // Emit an event for bookkeeping / bridge monitoring
        emit Withdrawal(_token, _recipient, _amount);
    }

    function registerToken(address _token) public onlyRole(ADMIN_ROLE) {
        // Prevent registration of the zero address
        require(_token != address(0), "Invalid token");

        // Prevent duplicate registration
        require(!approved[_token], "Already registered");

        // Mark the token as approved
        approved[_token] = true;

        // Track the token in the list of registered bridgeable assets
        tokens.push(_token);

        // Emit a registration event
        emit Registration(_token);
    }
}