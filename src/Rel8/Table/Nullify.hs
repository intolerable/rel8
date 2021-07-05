{-# language DataKinds #-}
{-# language FlexibleInstances #-}
{-# language LambdaCase #-}
{-# language MultiParamTypeClasses #-}
{-# language ScopedTypeVariables #-}
{-# language StandaloneKindSignatures #-}
{-# language TypeApplications #-}
{-# language TypeFamilies #-}
{-# language UndecidableInstances #-}

module Rel8.Table.Nullify
  ( Nullify
  , aggregateNullify
  , guard
  )
where

-- base
import Control.Applicative ( liftA2 )
import Control.Category ( id )
import Data.Functor.Identity ( runIdentity )
import Data.Kind ( Type )
import Data.Type.Equality ( (:~:)( Refl ), apply )
import Prelude hiding ( id )

-- comonad
import Control.Comonad ( Comonad, duplicate, extract, ComonadApply, (<@>) )

-- rel8
import Rel8.Aggregate ( Aggregate )
import Rel8.Expr ( Expr )
import Rel8.Kind.Context ( Reifiable, contextSing )
import Rel8.Schema.Context ( Col )
import Rel8.Schema.Context.Abstract ( Abstract, exclusivity, virtual )
import Rel8.Schema.Context.Nullify
  ( Nullifiability( NAggregate, NExpr )
  , NonNullifiability( NNReify )
  , Nullifiable, nullifiability
  , nullifiableOrNot, absurd
  , guarder
  , nullifier
  , unnullifier
  )
import Rel8.Schema.Dict ( Dict( Dict ) )
import Rel8.Schema.HTable ( HTable )
import Rel8.Schema.HTable.Nullify ( HNullify, hnullify, hunnullify, hguard )
import qualified Rel8.Schema.Kind as K
import Rel8.Schema.Reify ( hreify, hunreify )
import Rel8.Schema.Spec ( Spec( Spec ) )
import Rel8.Table
  ( Table, Columns, Context, toColumns, fromColumns
  , reify, unreify, coherence, congruence
  )
import Rel8.Table.Eq ( EqTable, eqTable )
import Rel8.Table.Ord ( OrdTable, ordTable )
import Rel8.Table.Recontextualize ( Recontextualize )

-- semigroupoids
import Data.Functor.Apply ( Apply, (<.>), liftF2 )
import Data.Functor.Bind ( Bind, (>>-) )
import Data.Functor.Extend ( Extend, duplicated )


type Nullify :: K.Context -> Type -> Type
data Nullify context a
  = Table (Nullifiability context) a
  | Fields (NonNullifiability context) (HNullify (Columns a) (Col (Context a)))


instance Nullifiable context => Functor (Nullify context) where
  fmap f = \case
    Table nullifiable a -> Table nullifiable (f a)
    Fields notNullifiable _ -> absurd nullifiability notNullifiable


instance Nullifiable context => Foldable (Nullify context) where
  foldMap f = \case
    Table _ a -> f a
    Fields notNullifiable _ -> absurd nullifiability notNullifiable


instance Nullifiable context => Traversable (Nullify context) where
  traverse f = \case
    Table nullifiable a -> Table nullifiable <$> f a
    Fields notNullifiable _ -> absurd nullifiability notNullifiable


instance Nullifiable context => Apply (Nullify context) where
  liftF2 f = \case
    Table nullifiable a -> \case
      Table _ b -> Table nullifiable (f a b)
      Fields notNullifiable _ -> absurd nullifiable notNullifiable
    Fields notNullifiable _ -> absurd nullifiability notNullifiable


instance Nullifiable context => Applicative (Nullify context) where
  pure = Table nullifiability
  liftA2 = liftF2


instance Nullifiable context => Bind (Nullify context) where
  Table _ a >>- f = f a
  Fields notNullifiable _ >>- _ = absurd nullifiability notNullifiable


instance Nullifiable context => Monad (Nullify context) where
  (>>=) = (>>-)


instance Nullifiable context => Extend (Nullify context) where
  duplicated = \case
    Table nullifiable a -> Table nullifiable (Table nullifiable a)
    Fields notNullifiable _ -> absurd nullifiability notNullifiable


instance Nullifiable context => Comonad (Nullify context) where
  extract = \case
    Table _ a -> a
    Fields notNullifiable _ -> absurd nullifiability notNullifiable
  duplicate = duplicated


instance Nullifiable context => ComonadApply (Nullify context) where
  (<@>) = (<.>)


instance
  ( Table context a
  , Reifiable context, Abstract context, context ~ context'
  )
  => Table context' (Nullify context a)
 where
  type Columns (Nullify context a) = HNullify (Columns a)
  type Context (Nullify context a) = Context a

  fromColumns = case nullifiableOrNot contextSing of
    Left notNullifiable -> Fields notNullifiable
    Right nullifiable ->
      Table nullifiable .
      fromColumns .
      runIdentity .
      hunnullify (\spec -> pure . unnullifier nullifiable spec)

  toColumns = \case
    Table nullifiable a -> hnullify (nullifier nullifiable) (toColumns a)
    Fields _ a -> a

  reify proof@Refl = \case
    Table nullifiable a -> Table nullifiable (reify proof a)
    Fields notNullifiable a -> case notNullifiable of
      NNReify (_ :: NonNullifiability ctx) ->
        case coherence @context @a proof abstract of
          Refl -> case congruence @context @a proof abstract of
            Refl -> Fields notNullifiable (hreify a)
        where
          abstract = exclusivity (virtual @ctx)

  unreify proof@Refl = \case
    Table nullifiable a -> Table nullifiable (unreify proof a)
    Fields notNullifiable a -> case notNullifiable of
      NNReify (_ :: NonNullifiability ctx) ->
        case coherence @context @a proof abstract of
          Refl -> case congruence @context @a proof abstract of
            Refl -> Fields notNullifiable (hunreify a)
        where
          abstract = exclusivity (virtual @ctx)

  coherence = coherence @context @a
  congruence proof abstract = id `apply` congruence @context @a proof abstract


instance
  ( Recontextualize from to a b
  , Reifiable from, Abstract from, from ~ from'
  , Reifiable to, Abstract to, to ~ to'
  )
  => Recontextualize from' to' (Nullify from a) (Nullify to b)


instance (EqTable a, context ~ Expr) => EqTable (Nullify context a) where
  eqTable = hnullify (\_ Dict -> Dict) (eqTable @a)


instance (OrdTable a, context ~ Expr) => OrdTable (Nullify context a) where
  ordTable = hnullify (\_ Dict -> Dict) (ordTable @a)


aggregateNullify :: ()
  => (exprs -> aggregates)
  -> Nullify Expr exprs
  -> Nullify Aggregate aggregates
aggregateNullify f = \case
  Table _ a -> Table NAggregate (f a)
  Fields notNullifiable _ -> absurd NExpr notNullifiable


guard :: (Reifiable context, HTable t)
  => Col context ('Spec tag)
  -> (tag -> Bool)
  -> (Expr tag -> Expr Bool)
  -> HNullify t (Col context)
  -> HNullify t (Col context)
guard tag isNonNull isNonNullExpr =
  hguard (guarder contextSing tag isNonNull isNonNullExpr)