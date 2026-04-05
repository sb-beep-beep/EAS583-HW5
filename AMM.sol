// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol"; //This allows role-based access control through _grantRole() and the modifier onlyRole
import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; //This contract needs to interact with ERC20 tokens

contract AMM is AccessControl{
    bytes32 public constant LP_ROLE = keccak256("LP_ROLE");
    uint256 public invariant;
    address public tokenA;
    address public tokenB;
    uint256 feebps = 3; //The fee in basis points (i.e., the fee should be feebps/10000)

    event Swap( address indexed _inToken, address indexed _outToken, uint256 inAmt, uint256 outAmt );
    event LiquidityProvision( address indexed _from, uint256 AQty, uint256 BQty );
    event Withdrawal( address indexed _from, address indexed recipient, uint256 AQty, uint256 BQty );

    /*
        Constructor sets the addresses of the two tokens
    */
    constructor( address _tokenA, address _tokenB ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender );
        _grantRole(LP_ROLE, msg.sender);

        require( _tokenA != address(0), "Token address cannot be 0" );
        require( _tokenB != address(0), "Token address cannot be 0" );
        require( _tokenA != _tokenB, "Tokens cannot be the same" );
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function getTokenAddress( uint256 index ) public view returns(address) {
        require( index < 2, "Only two tokens" );
        if( index == 0 ) {
            return tokenA;
        } else {
            return tokenB;
        }
    }

    /*
        The main trading functions
        
        User provides sellToken and sellAmount

        The contract must calculate buyAmount using the formula:
    */
    function tradeTokens( address sellToken, uint256 sellAmount ) public {
        require( invariant > 0, "Invariant must be nonzero" );
        require( sellToken == tokenA || sellToken == tokenB, "Invalid token" );
        require( sellAmount > 0, "Cannot trade 0" );
        require( invariant > 0, "No liquidity" );

        uint256 qtyA;
        uint256 qtyB;
        uint256 swapAmt;

        // Reserve balances before the user's input token is pulled in
        qtyA = ERC20(tokenA).balanceOf(address(this));
        qtyB = ERC20(tokenB).balanceOf(address(this));

        // Fee is charged on the deposit side only
        uint256 effectiveSellAmount = (sellAmount * (10000 - feebps)) / 10000;
        require( effectiveSellAmount > 0, "Trade amount too small" );

        if( sellToken == tokenA ) {
            // User sells tokenA and receives tokenB
            require( qtyA > 0 && qtyB > 0, "No liquidity" );

            // swapAmt = amount of tokenB to send out
            swapAmt = (qtyB * effectiveSellAmount) / (qtyA + effectiveSellAmount);
            require( swapAmt > 0, "Swap amount is 0" );
            require( swapAmt < qtyB, "Insufficient tokenB liquidity" );

            // Pull tokenA from sender into this contract
            require(
                ERC20(tokenA).transferFrom(msg.sender, address(this), sellAmount),
                "tokenA transferFrom failed"
            );

            // Send tokenB out to sender
            require(
                ERC20(tokenB).transfer(msg.sender, swapAmt),
                "tokenB transfer failed"
            );

            emit Swap( tokenA, tokenB, sellAmount, swapAmt );
        } else {
            // User sells tokenB and receives tokenA
            require( qtyA > 0 && qtyB > 0, "No liquidity" );

            // swapAmt = amount of tokenA to send out
            swapAmt = (qtyA * effectiveSellAmount) / (qtyB + effectiveSellAmount);
            require( swapAmt > 0, "Swap amount is 0" );
            require( swapAmt < qtyA, "Insufficient tokenA liquidity" );

            // Pull tokenB from sender into this contract
            require(
                ERC20(tokenB).transferFrom(msg.sender, address(this), sellAmount),
                "tokenB transferFrom failed"
            );

            // Send tokenA out to sender
            require(
                ERC20(tokenA).transfer(msg.sender, swapAmt),
                "tokenA transfer failed"
            );

            emit Swap( tokenB, tokenA, sellAmount, swapAmt );
        }

        uint256 new_invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
        require( new_invariant >= invariant, "Bad trade" );
        invariant = new_invariant;
    }

    /*
        Use the ERC20 transferFrom to "pull" amtA of tokenA and amtB of tokenB from the sender
    */
    function provideLiquidity( uint256 amtA, uint256 amtB ) public {
        require( amtA > 0 || amtB > 0, "Cannot provide 0 liquidity" );

        if( amtA > 0 ) {
            require(
                ERC20(tokenA).transferFrom(msg.sender, address(this), amtA),
                "tokenA transferFrom failed"
            );
        }

        if( amtB > 0 ) {
            require(
                ERC20(tokenB).transferFrom(msg.sender, address(this), amtB),
                "tokenB transferFrom failed"
            );
        }

        invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
        emit LiquidityProvision( msg.sender, amtA, amtB );
    }

    /*
        Use the ERC20 transfer function to send amtA of tokenA and amtB of tokenB to the target recipient
        The modifier onlyRole(LP_ROLE) 
    */
    function withdrawLiquidity( address recipient, uint256 amtA, uint256 amtB ) public onlyRole(LP_ROLE) {
        require( amtA > 0 || amtB > 0, "Cannot withdraw 0" );
        require( recipient != address(0), "Cannot withdraw to 0 address" );

        if( amtA > 0 ) {
            require(
                ERC20(tokenA).transfer(recipient, amtA),
                "tokenA transfer failed"
            );
        }

        if( amtB > 0 ) {
            require(
                ERC20(tokenB).transfer(recipient, amtB),
                "tokenB transfer failed"
            );
        }

        invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
        emit Withdrawal( msg.sender, recipient, amtA, amtB );
    }
}