const { ethers } = require("hardhat");
require("dotenv").config({ path: ".env" });
const fs = require("fs")
const process = require("process")

function one_lb(tokenid: number) {
    console.log("inside");

    let ONE_POUND ={
        "tokenid" : tokenid,
        "name": "LUX Uranium",
        "symbol": "U",
        "description": "Backed by one pound of Uranium (U3O8) from the Madison North mine.",
        "seller_fee_basis_points": 500,
        "image": "https://bafkreie257sonrjtpxkyo6jymz7dfn3dytzu24bxo3nmlfwnzupkup7az4.ipfs.nftstorage.link",
        "external_url": "https://lux.market",
        "edition": "Jawn",
        "attributes": [
        {
            "trait_type": "Pounds",
            "value": "1"
        },
        {
            "trait_type": "Type",
            "value": "43-101 Verified"
        },
        {
            "trait_type": "Location",
            "value": "Madison North, RÃ¶ssing Formation, Namibia"
        },
        {
            "trait_type": "Issuer",
            "value": "Madison Metals"
        },
        {
            "trait_type": "Auditor",
            "value": "SRK Consulting (UK) Limited"
        }
        ],
        "properties": {
        "category": "video",
        "files": [
            {
            "uri": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link",
            "type": "video/mp4"
            }
        ],
        "creators": [
            {
            "address": "0xaF609ef0f3b682B5992c7A2Ecc0485afD4816d54",
            "share": 100
            }
        ]
        },
        "animation_url": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link"
    }

   return (
    JSON.stringify(ONE_POUND)
   );
}
function ten_lb(tokenid: number) {
    let TEN_POUNDS ={
        "name": "LUX Uranium",
        "tokenid" : tokenid,
        "symbol": "U",
        "description": "Backed by ten pounds of Uranium (U3O8) from the Madison North mine.",
        "seller_fee_basis_points": 500,
        "image": "https://bafkreie257sonrjtpxkyo6jymz7dfn3dytzu24bxo3nmlfwnzupkup7az4.ipfs.nftstorage.link",
        "external_url": "https://lux.market",
        "edition": "Jawn",
        "attributes": [
        {
            "trait_type": "Pounds",
            "value": "10"
        },
        {
            "trait_type": "Type",
            "value": "43-101 Verified"
        },
        {
            "trait_type": "Location",
            "value": "Madison North, RÃ¶ssing Formation, Namibia"
        },
        {
            "trait_type": "Issuer",
            "value": "Madison Metals"
        },
        {
            "trait_type": "Auditor",
            "value": "SRK Consulting (UK) Limited"
        }
        ],
        "properties": {
        "category": "video",
        "files": [
            {
            "uri": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link",
            "type": "video/mp4"
            }
        ],
        "creators": [
            {
            "address": "0xaF609ef0f3b682B5992c7A2Ecc0485afD4816d54",
            "share": 100
            }
        ]
        },
        "animation_url": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link"
    }

   return (
    JSON.stringify(TEN_POUNDS)
   );
}
function hundred_lbs(tokenid) {
    let HUNDRED_POUNDS ={
        "name": "LUX Uranium",
        "symbol": "U",
        "tokenid" : tokenid,
        "description": "Backed by one hundred pounds of Uranium (U3O8) from the Madison North mine.",
        "seller_fee_basis_points": 500,
        "image": "https://bafkreie257sonrjtpxkyo6jymz7dfn3dytzu24bxo3nmlfwnzupkup7az4.ipfs.nftstorage.link",
        "external_url": "https://lux.market",
        "edition": "Jawn",
        "attributes": [
        {
            "trait_type": "Pounds",
            "value": "100"
        },
        {
            "trait_type": "Type",
            "value": "43-101 Verified"
        },
        {
            "trait_type": "Location",
            "value": "Madison North, RÃ¶ssing Formation, Namibia"
        },
        {
            "trait_type": "Issuer",
            "value": "Madison Metals"
        },
        {
            "trait_type": "Auditor",
            "value": "SRK Consulting (UK) Limited"
        }
        ],
        "properties": {
        "category": "video",
        "files": [
            {
            "uri": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link",
            "type": "video/mp4"
            }
        ],
        "creators": [
            {
            "address": "0xaF609ef0f3b682B5992c7A2Ecc0485afD4816d54",
            "share": 100
            }
        ]
        },
        "animation_url": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link"
    }

   return (
    JSON.stringify(HUNDRED_POUNDS)
   );
}
function thousand_lbs(tokenid) {
    let THOUSAND_POUNDS ={
        "name": "LUX Uranium",
        "symbol": "U",
        "tokenid" : tokenid,
        "description": "Backed by one thousand pounds of Uranium (U3O8) from the Madison North mine.",
        "seller_fee_basis_points": 500,
        "image": "https://bafkreie257sonrjtpxkyo6jymz7dfn3dytzu24bxo3nmlfwnzupkup7az4.ipfs.nftstorage.link",
        "external_url": "https://lux.market",
        "edition": "Jawn",
        "attributes": [
        {
            "trait_type": "Pounds",
            "value": "1000"
        },
        {
            "trait_type": "Type",
            "value": "43-101 Verified"
        },
        {
            "trait_type": "Location",
            "value": "Madison North, RÃ¶ssing Formation, Namibia"
        },
        {
            "trait_type": "Issuer",
            "value": "Madison Metals"
        },
        {
            "trait_type": "Auditor",
            "value": "SRK Consulting (UK) Limited"
        }
        ],
        "properties": {
        "category": "video",
        "files": [
            {
            "uri": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link",
            "type": "video/mp4"
            }
        ],
        "creators": [
            {
            "address": "0xaF609ef0f3b682B5992c7A2Ecc0485afD4816d54",
            "share": 100
            }
        ]
        },
        "animation_url": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link"
    }
   return (
    JSON.stringify(THOUSAND_POUNDS)
   );
}
function two_thousand_lbs(tokenid) {
    let TWO_THOUSAND_POUNDS = {
        "name": "LUX Uranium",
        "symbol": "U",
        "tokenid" : tokenid,
        "description": "Backed by two thousand pounds of Uranium (U3O8) from the Madison North mine.",
        "seller_fee_basis_points": 500,
        "image": "https://bafkreie257sonrjtpxkyo6jymz7dfn3dytzu24bxo3nmlfwnzupkup7az4.ipfs.nftstorage.link",
        "external_url": "https://lux.market",
        "edition": "Jawn",
        "attributes": [
        {
            "trait_type": "Pounds",
            "value": "2000"
        },
        {
            "trait_type": "Type",
            "value": "43-101 Verified"
        },
        {
            "trait_type": "Location",
            "value": "Madison North, RÃ¶ssing Formation, Namibia"
        },
        {
            "trait_type": "Issuer",
            "value": "Madison Metals"
        },
        {
            "trait_type": "Auditor",
            "value": "SRK Consulting (UK) Limited"
        }
        ],
        "properties": {
        "category": "video",
        "files": [
            {
            "uri": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link",
            "type": "video/mp4"
            }
        ],
        "creators": [
            {
            "address": "0xaF609ef0f3b682B5992c7A2Ecc0485afD4816d54",
            "share": 100
            }
        ]
        },
        "animation_url": "https://bafybeibajrcv6iuleltwr6jnwn3ggzzyc2sonbns3gcjjvy73q2fa6lewe.ipfs.nftstorage.link"
    }

   return (
    JSON.stringify(TWO_THOUSAND_POUNDS)
   );
}
function toHex(index){
    return `${process.cwd()}/vera_mint/${ethers.utils.hexZeroPad(ethers.utils.hexlify(index), 32).toString().slice(2,)}.json`
}

async function main() {  

    // ONE POUND x 0 - 999
    for (let i = 0; i < 1000; i++) {
        console.log(toHex(i));
        fs.writeFileSync(
            `${toHex(i)}`,
            one_lb(i),
            {
                encoding: "utf8",
                flag: "a+",
                mode: 0o666
            }
        );
    }

    // TEN Pounds x 100
    for (let i = 1000; i < 1100; i++) {
        console.log(toHex(i));
        fs.writeFileSync(
            `${toHex(i)}`,
            ten_lb(i),
            {
                encoding: "utf8",
                flag: "a+",
                mode: 0o666
            }
        );
    }

    // HUNDRED Pounds x 10
    for (let i = 1100; i < 1110; i++) {
        console.log(toHex(i));
        fs.writeFileSync(
        `${toHex(i)}`,
        hundred_lbs(i),
            {
                encoding: "utf8",
                flag: "a+",
                mode: 0o666
            }
        );
    }
    
    // THOUSAND x 1
    for (let i = 1100; i < 1110; i++) {
        console.log(toHex(i));
        fs.writeFileSync(
        `${toHex(i)}`,
        thousand_lbs(i),
            {
                encoding: "utf8",
                flag: "a+",
                mode: 0o666
            }
        );
    }    

    fs.writeFileSync(
        `${toHex(1110)}`,
        two_thousand_lbs(1110),
        {
            encoding: "utf8",
            flag: "a+",
            mode: 0o666
        }
    );
}

main()
.then(() => process.exit(0))
.catch((error)=> {
    console.error(error);
    process.exit(1);
});

// 2,000	1	2,000	$70,000	$70,000
				
// 100	10	1,000	$35,000	$3,500

// 10	100	1,000	$35,000	$350
// 1	1,000	1,000	$35,000	$35
				

//bafybeics3tb4ms3c55ditmrdisxpp7w7q4wzbsj764eibcr75ir7qpanfu
//ipfs://bafybeics3tb4ms3c55ditmrdisxpp7w7q4wzbsj764eibcr75ir7qpanfu
//https://nftstorage.link/ipfs/bafybeics3tb4ms3c55ditmrdisxpp7w7q4wzbsj764eibcr75ir7qpanfu
//0x6d7914AF9CA056E16d50a67e0Fe9Ff818272156a

