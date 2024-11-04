import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/VestingV1.tact',
    options: {
        debug: true,
    },
};
