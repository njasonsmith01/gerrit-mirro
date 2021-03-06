# Copyright (C) 2016 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# War packaging.

jar_filetype = FileType(['.jar'])

LIBS = [
  '//gerrit-war:init',
  '//gerrit-war:log4j-config',
  '//gerrit-war:version',
  '//lib:postgresql',
  '//lib/log:impl_log4j',
]

PGMLIBS = [
  '//gerrit-pgm:pgm'
]

def _add_context(in_file, output):
  input_path = in_file.path
  return [
    'unzip -qd %s %s' % (output, input_path)
  ]

def _add_file(in_file, output):
  output_path = output
  input_path = in_file.path
  short_path = in_file.short_path
  n = in_file.basename

  # TODO(davido): Drop this when provided_deps added to java_library
  if n.find('-jdk15on-') != -1:
    return []

  if short_path.startswith('gerrit-'):
    n = short_path.split('/')[0] + '-' + n

  output_path += n
  return [
    'test -L %s || ln -s $(pwd)/%s %s' % (output_path, input_path, output_path)
  ]

def _make_war(input_dir, output):
  return ''.join([
    '(root=$(pwd) && ',
    'cd %s && ' % input_dir,
    'zip -9qr ${root}/%s .)' % (output.path),
  ])

def _war_impl(ctx):
  war = ctx.outputs.war
  build_output = war.path + '.build_output'
  inputs = []

  # Create war layout
  cmd = [
    'set -e;rm -rf ' + build_output,
    'mkdir -p ' + build_output,
    'mkdir -p %s/WEB-INF/lib' % build_output,
    'mkdir -p %s/WEB-INF/pgm-lib' % build_output,
  ]

  # Add lib
  transitive_lib_deps = set()
  for l in ctx.attr.libs:
    transitive_lib_deps += l.java.transitive_runtime_deps

  for dep in transitive_lib_deps:
    cmd += _add_file(dep, build_output + '/WEB-INF/lib/')
    inputs.append(dep)

  # Add pgm lib
  transitive_pgmlib_deps = set()
  for l in ctx.attr.pgmlibs:
    transitive_pgmlib_deps += l.java.transitive_runtime_deps

  for dep in transitive_pgmlib_deps:
    if dep not in inputs:
      cmd += _add_file(dep, build_output + '/WEB-INF/pgm-lib/')
      inputs.append(dep)

  # Add context
  transitive_context_deps = set()
  if ctx.attr.context:
    for jar in ctx.attr.context:
      if hasattr(jar, 'java'):
        transitive_context_deps += jar.java.transitive_runtime_deps
      elif hasattr(jar, 'files'):
        transitive_context_deps += jar.files
  for dep in transitive_context_deps:
    cmd += _add_context(dep, build_output)
    inputs.append(dep)

  # Add zip war
  cmd.append(_make_war(build_output, war))

  ctx.action(
    inputs = inputs,
    outputs = [war],
    mnemonic = 'WAR',
    command = '\n'.join(cmd),
    use_default_shell_env = True,
  )

_pkg_war = rule(
  attrs = {
    'context': attr.label_list(allow_files = True),
    'libs': attr.label_list(allow_files = jar_filetype),
    'pgmlibs': attr.label_list(allow_files = False),
  },
  implementation = _war_impl,
  outputs = {'war' : '%{name}.war'},
)

def pkg_war(name, ui = 'ui_optdbg', context = [], **kwargs):
  ui_deps = []
  if ui:
    ui_deps.append('//gerrit-gwtui:%s' % ui)
  _pkg_war(
    name = name,
    libs = LIBS,
    pgmlibs = PGMLIBS,
    context = context + ui_deps + [
      '//gerrit-main:main_bin_deploy.jar',
      '//gerrit-war:webapp_assets',
    ],
    **kwargs
  )
