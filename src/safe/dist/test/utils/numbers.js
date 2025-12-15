"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getRandomIntAsString = exports.getRandomInt = void 0;
const getRandomInt = (min = 0, max = Number.MAX_SAFE_INTEGER) => {
    return Math.floor(Math.random() * (max - min + 1)) + min;
};
exports.getRandomInt = getRandomInt;
const getRandomIntAsString = (min = 0, max = Number.MAX_SAFE_INTEGER) => {
    return getRandomInt(min, max).toString();
};
exports.getRandomIntAsString = getRandomIntAsString;
