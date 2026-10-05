using Hydrogen.Compiler.IR;
using Hydrogen.Compiler.CodeGen.X64;
public class Program {
    public static int Main(string[] args) {
        IrMethod main = new IrMethod("Main", true, false, false, new IrType("int"), new IrParameter[0], IrStatement.Return(IrExpression.Literal("number", "41")));
        IrMethod[] methods = new IrMethod[1]; methods[0] = main;
        IrClass cl = new IrClass("Program", new IrField[0], methods);
        cl.SetImports(new IrImport[0]);
        IrClass[] classes = new IrClass[1]; classes[0] = cl;
        IrFunction function = new IrFunction("Program.Main", "int", new string[0]);
        function.SetDeclaration(main);
        IrFunction[] functions = new IrFunction[1]; functions[0] = function;
        IrModule module = new IrModule(functions);
        module.SetRoot(new IrUnit(new IrImport[0], new IrNamespace[0], classes, new IrEnum[0], new IrInterface[0]));
        DirectMainCompiler backend = new DirectMainCompiler();
        DirectImageResult first = backend.Compile(module);
        if (!first.Success()) { return 90; }
        System.IO.File.WriteAllBytes(args[0], first.Image());
        module.Functions()[0].SetBody(IrStatement.Return(IrExpression.Literal("number", "42")));
        DirectImageResult second = backend.Compile(module);
        if (!second.Success()) { return 91; }
        System.IO.File.WriteAllBytes(args[1], second.Image());
        return 0;
    }
}
