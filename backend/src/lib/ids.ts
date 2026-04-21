import { ulid } from 'ulid';

/**
 * Primary-key generator. Centralized so we can swap implementations later
 * (e.g. KSUIDs, Snowflake-likes) without a find-and-replace.
 */
export const newId = (): string => ulid();
