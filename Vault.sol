// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC20.sol";
import "https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMathQuad.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";

contract Vault {
    IERC20 public immutable token;
    uint public totalSupply;
    uint public longTotalSupply;        // total supply of long position
    uint public shortTotalSupply;       // total supply of short position
    uint public longTotalPrice;
    uint public shortTotalPrice;
    //mapping(address => uint) public balanceOf;
    mapping(address => uint) public longBalanceOf;      // balance of long position
    mapping(address => uint) public shortBalanceOf;     // balance of short position
    mapping(address => bytes16) public longDepositPrice;
    mapping(address => bytes16) public shortDepositPrice;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function _longMint(address _to, uint _amount, uint _depositPrice) private {
        totalSupply += _amount;
        longTotalSupply += _amount;
        longTotalPrice += _amount * _depositPrice;

        bytes16 prevBalance = ABDKMathQuad.fromUInt(longBalanceOf[_to]);
        bytes16 prevDeposit = longDepositPrice[_to];
        bytes16 temp1 = ABDKMathQuad.mul(prevBalance, prevDeposit);
        bytes16 temp2 = ABDKMathQuad.fromUInt(_amount * _depositPrice);
        bytes16 temp3 = ABDKMathQuad.fromUInt(longBalanceOf[_to] + _amount);
        bytes16 newDeposit = ABDKMathQuad.div(ABDKMathQuad.add(temp1, temp2),temp3);
        longBalanceOf[_to] += _amount;
        longDepositPrice[_to] = newDeposit;
    }

    function _shortMint(address _to, uint _amount, uint _depositPrice) private {
        totalSupply += _amount;
        shortTotalSupply += _amount;
        shortTotalPrice += _amount * _depositPrice;
        bytes16 prevBalance = ABDKMathQuad.fromUInt(shortBalanceOf[_to]);
        bytes16 prevDeposit = shortDepositPrice[_to];
        bytes16 temp1 = ABDKMathQuad.mul(prevBalance, prevDeposit);
        bytes16 temp2 = ABDKMathQuad.fromUInt(_amount * _depositPrice);
        bytes16 temp3 = ABDKMathQuad.fromUInt(shortBalanceOf[_to] + _amount);
        bytes16 newDeposit = ABDKMathQuad.div(ABDKMathQuad.add(temp1, temp2),temp3);
        shortBalanceOf[_to] += _amount;
        shortDepositPrice[_to] = newDeposit;
    }

    function _longBurn(address _from, uint _amount, uint _depositPrice) private {
        totalSupply -= _amount;
        longTotalSupply -= _amount;
        longTotalPrice -= _amount * _depositPrice;
//        balanceOf[_from] -= _shares;
        longBalanceOf[_from] -= _amount;
    }

    function _shortBurn(address _from, uint _amount, uint _depositPrice) private {
        totalSupply -= _amount;
        shortTotalSupply -= _amount;
        shortTotalPrice -= _amount * _depositPrice;
//        balanceOf[_from] -= _shares;
        shortBalanceOf[_from] -= _amount;
    }

    function deposit(uint _amount, uint _type, uint _depositPrice) external {
        // _type represents that a user deposit to long or short (long: 1, short: 0)
        // _leverage increases the return on equity capital by using other people's capital
        // we also need to the 'depositPrice', price at the time of deposit (Need to implement oracle)
        if (_type == 1){         // deposit to the long position
            _longMint(msg.sender, _amount, _depositPrice);
            token.transferFrom(msg.sender, address(this), _amount);
        } else if (_type == 0) {   // deposit to the short position
            _shortMint(msg.sender, _amount, _depositPrice);
            token.transferFrom(msg.sender, address(this), _amount);
        }
    }

    function withdraw(uint _amount, uint _type, uint _withdrawPrice) external {
        // _type represents that a user deposit to long or short (long: 1, short: 0)
        // we also need to the 'withdrawPrice', price at the time of withdraw (Need to implement oracle)
        // longEarn and shortEarn are neede for computing ratio of profit (or loss) between long position and short position.
        bytes16 longEarn;
        bytes16 shortEarn;

        if (longTotalSupply != 0){
            longEarn = ABDKMathQuad.sub(ABDKMathQuad.fromUInt(_withdrawPrice * longTotalSupply), ABDKMathQuad.fromUInt(longTotalPrice));
        } else{
            longEarn = ABDKMathQuad.fromUInt(0);
        }   

        if (shortTotalSupply != 0){
            shortEarn = ABDKMathQuad.sub(ABDKMathQuad.fromUInt(_withdrawPrice * shortTotalSupply), ABDKMathQuad.fromUInt(shortTotalPrice));
        } else{
            shortEarn = ABDKMathQuad.fromUInt(0);
        }

        if (_type == 1){         // withdraw to the long position
            uint result = 0;
            bytes16 tempResult1 = ABDKMathQuad.fromUInt(_amount);
            bytes16 tempResult2;
            bytes16 initialPrice = longDepositPrice[msg.sender];
            _longBurn(msg.sender, _amount, ABDKMathQuad.toUInt(initialPrice));
            if (ABDKMathQuad.cmp(longEarn, shortEarn) == 1){
                //tempResult2 = ABDKMathQuad.div(ABDKMathQuad.mul(ABDKMathQuad.sub(ABDKMathQuad.fromUInt(_withdrawPrice), initialPrice), shortEarn), longEarn);
                tempResult2 = ABDKMathQuad.sub(ABDKMathQuad.fromUInt(_withdrawPrice), initialPrice);
                result = ABDKMathQuad.toUInt(ABDKMathQuad.add(tempResult1, tempResult2));
            } else{
                tempResult2 = ABDKMathQuad.sub(initialPrice, ABDKMathQuad.fromUInt(_withdrawPrice));
                result = ABDKMathQuad.toUInt(ABDKMathQuad.sub(tempResult1, tempResult2));
            }
            token.transfer(msg.sender, result);
        } else if (_type == 0) {   // withdraw to the short position
            uint result = 0;
            bytes16 tempResult1 = ABDKMathQuad.fromUInt(_amount);
            bytes16 tempResult2;
            bytes16 initialPrice = longDepositPrice[msg.sender];
            _shortBurn(msg.sender, _amount, ABDKMathQuad.toUInt(initialPrice));
            if (ABDKMathQuad.cmp(shortEarn, longEarn) == 1){
                // tempResult2 = ABDKMathQuad.div(ABDKMathQuad.mul(ABDKMathQuad.sub(initialPrice, ABDKMathQuad.fromUInt(_withdrawPrice)), longEarn), shortEarn);
                tempResult2 = ABDKMathQuad.sub(initialPrice, ABDKMathQuad.fromUInt(_withdrawPrice));
                result = ABDKMathQuad.toUInt(ABDKMathQuad.add(tempResult1, tempResult2));
            } else{
                tempResult2 = ABDKMathQuad.sub(initialPrice, ABDKMathQuad.fromUInt(_withdrawPrice));
                result = ABDKMathQuad.toUInt(ABDKMathQuad.sub(tempResult1, tempResult2));
            }
            token.transfer(msg.sender, result);
        }
    }
}