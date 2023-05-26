// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../interfaces/ICar.sol";

/*
Created by the Uniswap team
 */

// accelerates to optimize turns-to-win
contract Speed is ICar {
    uint256 constant FLOOR = 5;

    function takeYourTurn(
        Monaco monaco,
        Monaco.CarData[] calldata allCars,
        uint256[] calldata /*bananas*/,
        uint256 ourCarIndex
    ) external override {
        Monaco.CarData memory ourCar = allCars[ourCarIndex];
        uint256 turnsToWin = ourCar.speed == 0 ? 1000 : (1000 - ourCar.y) / ourCar.speed;
        (uint256 turnsToLose, uint256 bestOpponentIdx) = getTurnsToLoseOptimistic(monaco, allCars, ourCarIndex);

        uint32 enemy1Speed = 0;
        uint32 enemy2Speed = 0;

        if (ourCarIndex == 0) {
            enemy1Speed = allCars[1].speed;
            enemy2Speed = allCars[2].speed;
        } else if (ourCarIndex == 1) {
            enemy1Speed = allCars[0].speed;
            enemy2Speed = allCars[2].speed;
        } else if (ourCarIndex == 2) {
            enemy1Speed = allCars[0].speed;
            enemy2Speed = allCars[1].speed;
        }

        // shoot until everyone is starting to race
        // Khi nao di thi tat ca cung di
        if (enemy1Speed == 0 || enemy2Speed == 0) {
            if (monaco.getSuperShellCost(1) < FLOOR) {
                superShell(monaco, ourCar, 1);
            }
            if (monaco.getShellCost(1) < FLOOR) {
                shell(monaco, ourCar, 1);
            }
            return;
        }

        // if we can buy enough acceleration to win right away, do it
        uint256 accelToWin = (1000 - ourCar.y) - ourCar.speed;
        uint256 maxAcc = maxAccel(monaco, ourCar.balance);
        if (maxAcc >= accelToWin) {
            accelerate(monaco, ourCar, accelToWin);
            stopOpponent(monaco, allCars, ourCar, ourCarIndex, bestOpponentIdx, 100000);
            accelerate(monaco, ourCar, maxAcc);
            return;
        }

        // 'tryLowerTurnsToWin' will use the remaining balance to accelerate as much as possible
        // preventing too much balance when game ends
        uint256 maxAccelCost = turnsToLose == 0 ? 100000 : turnsToLose < 6 ? 5000 / turnsToLose : 10 + (1000 / turnsToLose);
        if (!tryLowerTurnsToWin(monaco, ourCar, turnsToWin, maxAccelCost)) {
            accelerate(monaco, ourCar, 2);
        }

        // almost lost, so shoot them all :))
        if (turnsToLose < 3) {
            superShell(monaco, ourCar, 1);
        }

        // if the position is good and the price of items is cheap, buy them
        if (ourCarIndex != 0 && monaco.getShellCost(1) < FLOOR) {
            shell(monaco, ourCar, 1);
        }
        if (ourCarIndex == 2 && monaco.getSuperShellCost(1) < FLOOR) {
            superShell(monaco, ourCar, 1);
        }
        // If the position is good and the price of items is cheap, buy them, but not if other cars do not have enough money
        if (ourCarIndex != 2 && monaco.getShieldCost(1) < FLOOR
            && allCars[2].balance > monaco.getShellCost(1)
            && allCars[ourCarIndex+1].balance > monaco.getShellCost(1)
            ) {
            shield(monaco, ourCar, 1);
        }
        if (ourCarIndex != 2 && monaco.getBananaCost() < FLOOR
            && allCars[2].balance > monaco.getAccelerateCost(1)
            && allCars[ourCarIndex+1].balance > monaco.getAccelerateCost(1)
            ) {
            banana(monaco, ourCar);
        }
    }

    function tryLowerTurnsToWin(Monaco monaco, Monaco.CarData memory ourCar, uint256 turnsToWin, uint256 maxAccelCost) internal returns (bool success) {
        // Increase the speed at the end of race
        if (ourCar.y < 740) {
            return false;
        }

        uint256 maxAccelPossible = maxAccel(monaco, maxAccelCost > ourCar.balance ? ourCar.balance : maxAccelCost);
        if (maxAccelPossible == 0) {
            return false;
        }

        uint256 bestTurnsToWin = (1000 - ourCar.y) / (ourCar.speed + maxAccelPossible);

        // no amount of accel will lower our ttw
        if (bestTurnsToWin == turnsToWin) {
            return false;
        }

        // iterate down and see the least speeda that still gets the best ttw
        uint256 leastAccel = maxAccelPossible;
        for (uint256 accel = maxAccelPossible; accel > 0; accel--) {
            uint256 newTurnsToWin = (1000 - ourCar.y) / (ourCar.speed + accel);
            if (newTurnsToWin > bestTurnsToWin) {
                leastAccel = accel + 1;
                break;
            }
        }
        accelerate(monaco, ourCar, leastAccel);

        return true;
    }

    function accelToFloor(Monaco monaco, Monaco.CarData memory ourCar, uint256 turnsToLose) internal {
        uint256 floor = 5 + (500 / turnsToLose);
        while (monaco.getAccelerateCost(1) < floor) {
            if (!accelerate(monaco, ourCar, 1)) {
                return;
            }
        }
    }

    function stopOpponent(Monaco monaco, Monaco.CarData[] calldata allCars, Monaco.CarData memory ourCar, uint256 ourCarIdx, uint256 opponentIdx, uint256 maxCost) internal {
        // in front, so use shells
        if (opponentIdx < ourCarIdx) {
            // theyre already slow so no point shelling
            if (allCars[opponentIdx].speed == 1) {
                return;
            }

            if (!superShell(monaco, ourCar, 1)) {
                // TODO: try to send enough shells to kill all bananas and the oppo
                shell(monaco, ourCar, 1);
            }
        } else if (monaco.getBananaCost() < maxCost) {
            // behind so banana
            banana(monaco, ourCar);
        }
    }

    function getTurnsToLoseOptimistic(Monaco monaco, Monaco.CarData[] calldata allCars, uint256 ourCarIndex) internal returns (uint256 turnsToLose, uint256 bestOpponentIdx) {
        turnsToLose = 1000;
        for (uint256 i = 0; i < allCars.length; i++) {
            if (i != ourCarIndex) {
                Monaco.CarData memory car = allCars[i];
                uint256 maxSpeed = car.speed + maxAccel(monaco, car.balance * 6 / 10);
                uint256 turns = maxSpeed == 0 ? 1000 : (1000 - car.y) / maxSpeed;
                if (turns < turnsToLose) {
                    turnsToLose = turns;
                    bestOpponentIdx = i;
                }
            }
        }
    }

    function getTurnsToLose(Monaco monaco, Monaco.CarData[] calldata allCars, uint256 ourCarIndex) internal returns (uint256 turnsToLose, uint256 bestOpponentIdx) {
        turnsToLose = 1000;
        for (uint256 i = 0; i < allCars.length; i++) {
            if (i != ourCarIndex) {
                Monaco.CarData memory car = allCars[i];
                uint256 maxSpeed = car.speed + maxAccel(monaco, car.balance);
                uint256 turns = maxSpeed == 0 ? 1000 : (1000 - car.y) / maxSpeed;
                if (turns < turnsToLose) {
                    turnsToLose = turns;
                    bestOpponentIdx = i;
                }
            }
        }
    }

    // get max accelerate we can buy with our balance
    function maxAccel(Monaco monaco, uint256 balance) internal view returns (uint256 amount) {
        uint256 current = 7;
        uint256 min = 0;
        uint256 max = 14;
        while (max - min > 1) {
            uint256 cost = monaco.getAccelerateCost(current);
            if (cost > balance) {
                max = current;
            } else if (cost < balance) {
                min = current;
            } else {
                return current;
            }
            current = (max + min) / 2;
        }
        return min;
    }

    // get max shell we can buy with our balance
    function maxShell(Monaco monaco, uint256 balance) internal view returns (uint256 amount) {
        uint256 best = 0;
        for (uint256 i = 1; i < 1000; i++) {
            if (monaco.getShellCost(i) > balance) {
                return best;
            }
            best = i;
        }
    }

    // buy `amount` accelerates
    function accelerate(Monaco monaco, Monaco.CarData memory ourCar, uint256 amount) internal returns (bool success) {
        if (ourCar.balance > monaco.getAccelerateCost(amount)) {
            ourCar.balance -= uint32(monaco.buyAcceleration(amount));
            return true;
        }
        return false;
    }

    // buy `amount` shells
    function shell(Monaco monaco, Monaco.CarData memory ourCar, uint256 amount) internal returns (bool success) {
        if (ourCar.balance > monaco.getShellCost(amount)) {
            ourCar.balance -= uint32(monaco.buyShell(amount));
            return true;
        }
        return false;
    }

    // buy `amount` super shells
    function superShell(Monaco monaco, Monaco.CarData memory ourCar, uint256 amount) internal returns (bool success) {
        if (ourCar.balance > monaco.getSuperShellCost(amount)) {
            ourCar.balance -= uint32(monaco.buySuperShell(amount));
            return true;
        }
        return false;
    }

    // buy `amount` shields
    function shield(Monaco monaco, Monaco.CarData memory ourCar, uint256 amount) internal returns (bool success) {
        if (ourCar.balance > monaco.getShieldCost(amount)) {
            ourCar.balance -= uint32(monaco.buyShield(amount));
            return true;
        }
        return false;
    }

    // buy a banana
    function banana(Monaco monaco, Monaco.CarData memory ourCar) internal returns (bool success) {
        if (ourCar.balance > monaco.getBananaCost()) {
            ourCar.balance -= uint32(monaco.buyBanana());
            return true;
        }
        return false;
    }

    function sayMyName() external pure returns (string memory) {
        return "Loki";
    }
}
