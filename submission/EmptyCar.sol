// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./../interfaces/ICar.sol";

contract EmptyCar is ICar {
    function takeYourTurn(
        Monaco monaco,
        Monaco.CarData[] calldata allCars,
        uint256[] calldata, /*bananas*/
        uint256 ourCarIndex
    ) external override {
        //donothing here
    }

    function sayMyName() external pure returns (string memory) {
        return "Empty Car";
    }
}
