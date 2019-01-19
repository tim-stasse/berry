import {Configuration, Plugin, Project} from '@berry/core';
import {scriptUtils}                    from '@berry/core';
// @ts-ignore: Need to write the definition file
import {UsageError}                     from '@manaflair/concierge';
import {Writable}                       from 'stream';

export default (concierge: any, plugins: Map<string, Plugin>) => concierge

  .command(`bin [name]`)
  .describe(`get the path to a binary script`)

  .action(async ({cwd, stdout, name}: {cwd: string, stdout: Writable, name: string}) => {
    const configuration = await Configuration.find(cwd, plugins);
    const {workspace} = await Project.find(configuration, cwd);

    const binaries = await scriptUtils.getWorkspaceAccessibleBinaries(workspace);

    if (name) {
      const binary = binaries.get(name);

      if (!binary)
        throw new UsageError(`Couldn't find a binary named "${name}"`);

      const [pkg, binaryFile] = binary;
      stdout.write(`${binaryFile}\n`);
    } else {
      for (const name of binaries.keys()) {
        stdout.write(`${name}\n`);
      }
    }
  });