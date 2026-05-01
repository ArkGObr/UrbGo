import re

with open('lib/features/auth/presentation/register_screen.dart', 'r') as f:
    content = f.read()

# We need to insert int _currentStep = 0;
content = re.sub(
    r'(String _selectedRole = \'client\';)',
    r'int _currentStep = 0;\n  \1',
    content
)

# And replace the build method.
# We'll split the build method content into steps.
build_start = content.find('  @override\n  Widget build(BuildContext context) {')
build_end = content.find('// ── Widget: Card de seleção de role', build_start)

build_content = content[build_start:build_end]

# It's better to construct the new build method and replace it.
new_build = """  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;
    final totalSteps = _selectedRole == 'client' ? 3 : 4;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xl2,
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom: AppSpacing.md,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_currentStep > 0) {
                        setState(() => _currentStep--);
                      } else {
                        context.go('/login');
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text('Criar conta', style: AppTypography.h2),
                ],
              ),
            ),
            
            // Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: List.generate(totalSteps, (index) {
                  final isActive = index <= _currentStep;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        right: index < totalSteps - 1 ? AppSpacing.xs : 0,
                      ),
                      height: 4,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary
                            : AppColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Form Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_currentStep == 0) _buildStep0Role(),
                      if (_currentStep == 1) _buildStep1PersonalInfo(),
                      if (_currentStep == 2) _buildStep2Details(),
                      if (_currentStep == 3 && _selectedRole == 'motoboy')
                        _buildStep3Documents(),

                      const SizedBox(height: AppSpacing.xl3),

                      PrimaryButton(
                        label: _currentStep < totalSteps - 1 ? 'Próximo' : 'Criar conta',
                        onPressed: isLoading
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  if (_currentStep < totalSteps - 1) {
                                    setState(() => _currentStep++);
                                  } else {
                                    _submit();
                                  }
                                }
                              },
                        isLoading: isLoading,
                      ),
                      const SizedBox(height: AppSpacing.xl2),

                      if (_currentStep == 0)
                        Center(
                          child: TextButton(
                            onPressed: () => context.go('/login'),
                            child: RichText(
                              text: TextSpan(
                                text: 'Já tem conta? ',
                                style: AppTypography.bodyMedium,
                                children: [
                                  TextSpan(
                                    text: 'Entrar',
                                    style: AppTypography.labelLarge.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xl2),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep0Role() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo de conta', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                icon: Icons.business_rounded,
                label: 'Sou Cliente',
                subtitle: 'Contrata entregas',
                value: 'client',
                selected: _selectedRole == 'client',
                onTap: () => setState(() => _selectedRole = 'client'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _RoleCard(
                icon: Icons.two_wheeler_rounded,
                label: 'Sou Entregador',
                subtitle: 'Faço entregas',
                value: 'motoboy',
                selected: _selectedRole == 'motoboy',
                onTap: () => setState(() => _selectedRole = 'motoboy'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep1PersonalInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Informações Pessoais', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Nome completo',
            prefixIcon: Icon(Icons.person_outlined, color: AppColors.textTertiary, size: 20),
          ),
          validator: (v) => Validators.required(v, field: 'Nome'),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [_PhoneMaskFormatter()],
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Telefone',
            hintText: '(00) 00000-0000',
            prefixIcon: Icon(Icons.phone_outlined, color: AppColors.textTertiary, size: 20),
          ),
          validator: Validators.phone,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'E-mail',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.textTertiary, size: 20),
          ),
          validator: Validators.email,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Senha',
            prefixIcon: const Icon(Icons.lock_outlined, color: AppColors.textTertiary, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.textTertiary,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: Validators.password,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _confirmPasswordCtrl,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.next,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Confirmar senha',
            prefixIcon: const Icon(Icons.lock_outlined, color: AppColors.textTertiary, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.textTertiary,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Confirme sua senha';
            if (v != _passwordCtrl.text) return 'As senhas não coincidem';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildStep2Details() {
    if (_selectedRole == 'client') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detalhes da Conta', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<String>(
            initialValue: _clientType,
            style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
            dropdownColor: AppColors.surface,
            decoration: InputDecoration(
              labelText: 'Tipo de Conta',
              prefixIcon: Icon(
                _clientType == 'cpf' ? Icons.person_outlined : Icons.business_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'cpf', child: Text('Pessoa Física (CPF)')),
              DropdownMenuItem(value: 'cnpj', child: Text('Empresa (CNPJ)')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _clientType = v;
                  _documentCtrl.clear();
                });
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: _documentCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_clientType == 'cpf' ? 11 : 14),
              _clientType == 'cpf' ? _CpfMaskFormatter() : _CnpjMaskFormatter(),
            ],
            style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: _clientType == 'cpf' ? 'CPF' : 'CNPJ',
              hintText: _clientType == 'cpf' ? '000.000.000-00' : '00.000.000/0000-00',
              prefixIcon: Icon(
                _clientType == 'cpf' ? Icons.badge_outlined : Icons.business_center_outlined,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ),
            validator: (v) {
              final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
              if (_clientType == 'cpf' && digits.length != 11) return 'CPF deve ter 11 dígitos';
              if (_clientType == 'cnpj' && digits.length != 14) return 'CNPJ deve ter 14 dígitos';
              return null;
            },
          ),
        ],
      );
    } else {
      // Motoboy Details
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detalhes do Entregador', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.lg),
          Text('Categoria do entregador', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'O cadastro será analisado com documentos obrigatórios de acordo com a categoria.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          CategorySelectorWidget(
            isForDriver: true,
            onSelected: (cat) => setState(() => _selectedCategory = cat),
          ),
          const SizedBox(height: AppSpacing.xl2),
          TextFormField(
            controller: _motoboyCpfCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
              _CpfMaskFormatter(),
            ],
            style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'CPF do entregador',
              hintText: '000.000.000-00',
              prefixIcon: Icon(Icons.badge_outlined, color: AppColors.textTertiary, size: 20),
            ),
            validator: (v) => Validators.cpf(v),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_selectedCategory != null && driverCategoryNeedsPlate(_selectedCategory!.category)) ...[
            TextFormField(
              controller: _plateCtrl,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Placa do veículo',
                hintText: 'Ex: ABC-1234',
                prefixIcon: Icon(Icons.two_wheeler_rounded, color: AppColors.textTertiary, size: 20),
              ),
              validator: (v) => Validators.required(v, field: 'Placa'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _modelCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Modelo do veículo',
                hintText: 'Ex: Honda CG 160',
                prefixIcon: Icon(Icons.directions_car_outlined, color: AppColors.textTertiary, size: 20),
              ),
              validator: (v) => Validators.required(v, field: 'Modelo do veículo'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _yearCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Ano do veículo',
                hintText: 'Ex: 2021',
                prefixIcon: Icon(Icons.calendar_today_outlined, color: AppColors.textTertiary, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ano do veículo é obrigatório';
                final year = int.tryParse(v);
                if (year == null || year < 1980 || year > 2035) return 'Ano inválido';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_selectedCategory != null && driverCategoryNeedsCnh(_selectedCategory!.category)) ...[
            TextFormField(
              controller: _cnhNumberCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Número de Registro da CNH',
                prefixIcon: Icon(Icons.credit_card_outlined, color: AppColors.textTertiary, size: 20),
              ),
              validator: (v) => Validators.required(v, field: 'Número da CNH'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _cnhCategoryCtrl,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                LengthLimitingTextInputFormatter(2),
              ],
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Categoria da CNH',
                hintText: 'Ex: A, B ou AB',
                prefixIcon: Icon(Icons.assignment_ind_outlined, color: AppColors.textTertiary, size: 20),
              ),
              validator: (v) => Validators.required(v, field: 'Categoria da CNH'),
            ),
            const SizedBox(height: AppSpacing.lg),
            InkWell(
              onTap: _pickCnhExpirationDate,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Validade da CNH',
                  prefixIcon: Icon(Icons.event_outlined, color: AppColors.textTertiary, size: 20),
                ),
                child: Text(
                  _cnhExpirationDate == null ? 'Selecione a data' : _formatDate(_cnhExpirationDate!),
                  style: AppTypography.bodyLarge.copyWith(
                    color: _cnhExpirationDate == null ? AppColors.textTertiary : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ]
        ],
      );
    }
  }

  Widget _buildStep3Documents() {
    if (_selectedCategory == null) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Envio de Documentos', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.lg),
        _DocumentsChecklistCard(
          category: _selectedCategory!.category,
          hasIdentityDocument: _identityDocumentFile != null,
          hasSelfieWithDocument: _selfieWithDocumentFile != null,
          hasAddressProof: _addressProofFile != null,
          hasVehicleDocument: _vehicleDocumentFile != null,
          hasAdditionalPermit: _additionalPermitFile != null,
        ),
        const SizedBox(height: AppSpacing.lg),
        _DocumentUploadTile(
          label: 'Documento de identificação',
          subtitle: 'RG ou documento oficial com foto',
          file: _identityDocumentFile,
          onTap: () => _pickDocument((file) => _identityDocumentFile = file),
        ),
        const SizedBox(height: AppSpacing.md),
        _DocumentUploadTile(
          label: 'Selfie com documento',
          subtitle: 'Foto do rosto segurando o documento visível',
          file: _selfieWithDocumentFile,
          onTap: () => _pickDocument((file) => _selfieWithDocumentFile = file),
        ),
        const SizedBox(height: AppSpacing.md),
        _DocumentUploadTile(
          label: 'Comprovante de residência',
          subtitle: 'Conta recente em nome do entregador',
          file: _addressProofFile,
          onTap: () => _pickDocument((file) => _addressProofFile = file),
        ),
        if (driverCategoryNeedsVehicleDocument(_selectedCategory!.category)) ...[
          const SizedBox(height: AppSpacing.md),
          _DocumentUploadTile(
            label: 'Documento do veículo',
            subtitle: 'CRLV ou equivalente',
            file: _vehicleDocumentFile,
            onTap: () => _pickDocument((file) => _vehicleDocumentFile = file),
          ),
        ],
        if (driverCategoryNeedsAdditionalPermit(_selectedCategory!.category)) ...[
          const SizedBox(height: AppSpacing.md),
          _DocumentUploadTile(
            label: driverAdditionalPermitLabel(_selectedCategory!.category),
            subtitle: 'Envie a licença complementar exigida para operar',
            file: _additionalPermitFile,
            onTap: () => _pickDocument((file) => _additionalPermitFile = file),
          ),
        ],
      ],
    );
  }
"""

new_content = content[:build_start] + new_build + '\n' + content[build_end:]

with open('lib/features/auth/presentation/register_screen.dart', 'w') as f:
    f.write(new_content)

print("Done!")
