pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import './Market.sol';


contract Barzar is Ownable{
    using SafeMath for uint256;

    bytes32[] marketList;
    mapping (bytes32 => address) mktIdAddressMap;
    mapping (address => bool) marketStatus;
    mapping (address => address[]) sellerMarketMap;


    function createMarket(string memory _productName,
                string memory _description,string memory _imageURL,uint _daysToExpiry)
                public
                payable
                returns (bytes32)
    {
        Market newMarket = (new Market).value(msg.value)(msg.sender,_productName,_description,
                            _imageURL,_daysToExpiry);
        bytes32 mktId = newMarket.getMarketId();
        mktIdAddressMap[mktId] = address(newMarket);
        marketList.push(mktId);
        marketStatus[address(newMarket)] = true;
        sellerMarketMap[msg.sender].push(address(newMarket));
    }

    function getMarket(bytes32 _marketID) public view returns (Market)
    {
        if (mktIdAddressMap[_marketID] == address(0)){
            revert ("No market with that ID");
        }

        else {
            return Market(mktIdAddressMap[_marketID]);
        }
    }

    function getMarketStatus(bytes32 _marketID) public view returns (bool)
    {
        return marketStatus[mktIdAddressMap[_marketID]];
    }

    function getMarketList() public returns (bytes32[] memory)
    {
        return (marketList);
    }


}